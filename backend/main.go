package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/gorilla/mux"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Entry struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Message   string    `json:"message"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB      *sql.DB
	Redis   *redis.Client
	Ctx     context.Context
	Metrics *Metrics
}

// Prometheus metrics
type Metrics struct {
	requestsTotal  *prometheus.CounterVec
	cacheHits      prometheus.Counter
	cacheMisses    prometheus.Counter
	dbEntriesTotal prometheus.Gauge
	httpDuration   *prometheus.HistogramVec
	dbUp           prometheus.Gauge
	redisUp        prometheus.Gauge
}

func NewMetrics() *Metrics {
	m := &Metrics{
		requestsTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "guestbook_requests_total",
				Help: "Total number of HTTP requests",
			},
			[]string{"method", "endpoint", "status"},
		),
		cacheHits: prometheus.NewCounter(
			prometheus.CounterOpts{
				Name: "guestbook_cache_hits_total",
				Help: "Total number of cache hits",
			},
		),
		cacheMisses: prometheus.NewCounter(
			prometheus.CounterOpts{
				Name: "guestbook_cache_misses_total",
				Help: "Total number of cache misses",
			},
		),
		dbEntriesTotal: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "guestbook_db_entries_total",
				Help: "Total number of entries in database",
			},
		),
		httpDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "guestbook_http_duration_seconds",
				Help:    "Duration of HTTP requests in seconds",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "endpoint"},
		),
		dbUp: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "guestbook_db_up",
				Help: "Database availability (1 = up, 0 = down)",
			},
		),
		redisUp: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "guestbook_redis_up",
				Help: "Redis availability (1 = up, 0 = down)",
			},
		),
	}

	// Register metrics
	prometheus.MustRegister(
		m.requestsTotal,
		m.cacheHits,
		m.cacheMisses,
		m.dbEntriesTotal,
		m.httpDuration,
		m.dbUp,
		m.redisUp,
	)

	return m
}

func main() {
	app := &App{
		Ctx:     context.Background(),
		Metrics: NewMetrics(),
	}

	// Initiera databas
	dbHost := getEnv("DB_HOST", "localhost")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "guestbook")
	dbPass := getEnv("DB_PASSWORD", "password")
	dbName := getEnv("DB_NAME", "guestbook")

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPass, dbName)

	var err error
	app.DB, err = sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal("Kunde inte ansluta till databasen:", err)
	}
	defer app.DB.Close()

	// Vänta på databas
	for i := 0; i < 30; i++ {
		err = app.DB.Ping()
		if err == nil {
			break
		}
		log.Println("Väntar på databas...")
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		log.Fatal("Databas inte tillgänglig:", err)
	}

	log.Println("✓ Ansluten till PostgreSQL")

	// Skapa tabell
	app.initDB()

	// Initiera Redis
	redisHost := getEnv("REDIS_HOST", "localhost")
	redisPort := getEnv("REDIS_PORT", "6379")
	redisPass := getEnv("REDIS_PASSWORD", "")

	app.Redis = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", redisHost, redisPort),
		Password: redisPass,
		DB:       0,
	})

	_, err = app.Redis.Ping(app.Ctx).Result()
	if err != nil {
		log.Println("⚠ Redis inte tillgänglig, fortsätter utan cache:", err)
	} else {
		log.Println("✓ Ansluten till Redis")
	}

	// Starta background job för att uppdatera metrik
	go app.updateMetricsPeriodically()

	// Setup router
	r := mux.NewRouter()

	// CORS middleware
	r.Use(corsMiddleware)

	// Prometheus metrics middleware
	r.Use(app.metricsMiddleware)

	// Routes
	r.HandleFunc("/health", app.healthHandler).Methods("GET")
	r.HandleFunc("/metrics", promhttp.Handler().ServeHTTP).Methods("GET")
	r.HandleFunc("/api/entries", app.getEntriesHandler).Methods("GET")
	r.HandleFunc("/api/entries", app.createEntryHandler).Methods("POST")
	r.HandleFunc("/api/entries/{id}", app.updateEntryHandler).Methods("PUT")
	r.HandleFunc("/api/entries/{id}", app.deleteEntryHandler).Methods("DELETE")
	r.HandleFunc("/api/stats", app.statsHandler).Methods("GET")

	port := getEnv("PORT", "8080")
	log.Printf("🚀 Server startar på port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}

func (app *App) initDB() {
	query := `
	CREATE TABLE IF NOT EXISTS entries (
		id SERIAL PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		message TEXT NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	)`

	_, err := app.DB.Exec(query)
	if err != nil {
		log.Fatal("Kunde inte skapa tabell:", err)
	}
	log.Println("✓ Databas-schema klart")
}

// Background job för att uppdatera metriker
func (app *App) updateMetricsPeriodically() {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		// Uppdatera DB entries count
		var count int
		err := app.DB.QueryRow("SELECT COUNT(*) FROM entries").Scan(&count)
		if err == nil {
			app.Metrics.dbEntriesTotal.Set(float64(count))
		}

		// Uppdatera DB status
		if err := app.DB.Ping(); err != nil {
			app.Metrics.dbUp.Set(0)
		} else {
			app.Metrics.dbUp.Set(1)
		}

		// Uppdatera Redis status
		if _, err := app.Redis.Ping(app.Ctx).Result(); err != nil {
			app.Metrics.redisUp.Set(0)
		} else {
			app.Metrics.redisUp.Set(1)
		}
	}
}

// Metrics middleware
func (app *App) metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Skip /metrics endpoint to avoid recursion
		if r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()

		// We use a custom ResponseWriter to capture the status code
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(rw, r)

		duration := time.Since(start).Seconds()

		// Record metrics
		app.Metrics.requestsTotal.WithLabelValues(
			r.Method,
			r.URL.Path,
			strconv.Itoa(rw.statusCode),
		).Inc()

		app.Metrics.httpDuration.WithLabelValues(
			r.Method,
			r.URL.Path,
		).Observe(duration)
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (app *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	health := map[string]interface{}{
		"status": "healthy",
		"time":   time.Now(),
	}

	if err := app.DB.Ping(); err != nil {
		health["database"] = "unhealthy"
		health["status"] = "degraded"
	} else {
		health["database"] = "healthy"
	}

	if _, err := app.Redis.Ping(app.Ctx).Result(); err != nil {
		health["redis"] = "unhealthy"
	} else {
		health["redis"] = "healthy"
	}

	json.NewEncoder(w).Encode(health)
}

func (app *App) getEntriesHandler(w http.ResponseWriter, r *http.Request) {
	cacheKey := "entries:all"

	if app.Redis != nil {
		cached, err := app.Redis.Get(app.Ctx, cacheKey).Result()
		if err == nil && cached != "" {
			log.Println("✓ Cache hit")
			app.Metrics.cacheHits.Inc()
			w.Header().Set("X-Cache", "HIT")
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(cached))
			return
		} else if err != nil {
			log.Printf("⚠ Cache miss (reason: %v)", err)
			app.Metrics.cacheMisses.Inc()
		}
	}

	// Hämta från databas
	rows, err := app.DB.Query(`
		SELECT id, name, message, created_at
		FROM entries
		ORDER BY created_at DESC
		LIMIT 100
	`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	entries := []Entry{}
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ID, &e.Name, &e.Message, &e.CreatedAt); err != nil {
			continue
		}
		entries = append(entries, e)
	}

	// Cacha resultatet
	if app.Redis != nil {
		jsonData, err := json.Marshal(entries)
		if err == nil {
			err = app.Redis.Set(app.Ctx, cacheKey, jsonData, 5*time.Minute).Err()
			if err == nil {
				log.Println("✓ Cache set (TTL: 5 minutes)")
			} else {
				log.Printf("⚠ Kunde inte sätta cache: %v", err)
			}
		}
	}

	w.Header().Set("X-Cache", "MISS")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(entries)
}

func (app *App) createEntryHandler(w http.ResponseWriter, r *http.Request) {
	var entry Entry
	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		http.Error(w, "Ogiltig data", http.StatusBadRequest)
		return
	}

	// Validering
	if entry.Name == "" || entry.Message == "" {
		http.Error(w, "Namn och meddelande krävs", http.StatusBadRequest)
		return
	}

	// Spara i databas
	err := app.DB.QueryRow(`
		INSERT INTO entries (name, message)
		VALUES ($1, $2)
		RETURNING id, created_at
	`, entry.Name, entry.Message).Scan(&entry.ID, &entry.CreatedAt)

	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Invalidera cache
	if app.Redis != nil {
		app.Redis.Del(app.Ctx, "entries:all")
		log.Println("🗑️ Cache invaliderad (create)")
		// Incrementera statistik
		app.Redis.Incr(app.Ctx, "stats:total_entries")
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(entry)
}

func (app *App) updateEntryHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	var entry Entry
	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		http.Error(w, "Ogiltig data", http.StatusBadRequest)
		return
	}

	// Validering
	if entry.Name == "" || entry.Message == "" {
		http.Error(w, "Namn och meddelande krävs", http.StatusBadRequest)
		return
	}

	// Uppdatera i databas
	result, err := app.DB.Exec(`
		UPDATE entries
		SET name = $1, message = $2
		WHERE id = $3
	`, entry.Name, entry.Message, id)

	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Kontrollera om posten hittades
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if rowsAffected == 0 {
		http.Error(w, "Inlägg hittades inte", http.StatusNotFound)
		return
	}

	// Invalidera cache
	if app.Redis != nil {
		app.Redis.Del(app.Ctx, "entries:all")
		log.Println("🗑️ Cache invaliderad (update)")
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Inlägget uppdaterat"})
}

func (app *App) deleteEntryHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	// Ta bort från databas
	result, err := app.DB.Exec("DELETE FROM entries WHERE id = $1", id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Kontrollera om posten hittades
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if rowsAffected == 0 {
		http.Error(w, "Inlägg hittades inte", http.StatusNotFound)
		return
	}

	// Invalidera cache
	if app.Redis != nil {
		app.Redis.Del(app.Ctx, "entries:all")
		log.Println("🗑️ Cache invaliderad (delete)")
		// Decrement statistics
		app.Redis.Decr(app.Ctx, "stats:total_entries")
	}

	w.WriteHeader(http.StatusNoContent)
}

func (app *App) statsHandler(w http.ResponseWriter, r *http.Request) {
	stats := make(map[string]interface{})

	// Räkna från databas
	var count int
	app.DB.QueryRow("SELECT COUNT(*) FROM entries").Scan(&count)
	stats["total_entries_db"] = count

	// Hämta från Redis om tillgängligt
	if app.Redis != nil {
		cacheCount, _ := app.Redis.Get(app.Ctx, "stats:total_entries").Result()
		stats["total_entries_created"] = cacheCount

		// Cache statistik
		info, _ := app.Redis.Info(app.Ctx, "stats").Result()
		if info != "" {
			stats["cache_available"] = true
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Expose-Headers", "X-Cache")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
