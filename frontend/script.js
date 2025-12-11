const entryForm = document.getElementById('entryForm');
const nameInput = document.getElementById('name');
const messageInput = document.getElementById('message');
const entriesList = document.getElementById('entriesList');
const totalEntriesEl = document.getElementById('totalEntries');
const cacheStatusEl = document.getElementById('cacheStatus');
const cacheTimestampEl = document.getElementById('cacheTimestamp');
const healthStatusEl = document.getElementById('healthStatus');
const sortSelect = document.getElementById('sortOrder');
const feedbackIcon = document.getElementById('feedback-icon');
const modalOverlay = document.getElementById('validationModal');
const modalText = document.getElementById('modalText');
const modalCloseBtn = document.getElementById('modalCloseBtn');

const deleteModal = document.getElementById('deleteConfirmModal');
const deleteCancelBtn = document.getElementById('deleteCancelBtn');
const deleteConfirmBtn = document.getElementById('deleteConfirmBtn');

const editModal = document.getElementById('editModal');
const editForm = document.getElementById('editForm');
const editNameInput = document.getElementById('editName');
const editMessageInput = document.getElementById('editMessage');
const editCancelBtn = document.getElementById('editCancelBtn');

let currentEntryId = null;

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}


let currentSound = null;

function playSound(type) {
    const soundMap = {
        'success': 'success-sound',
        'error': 'error-sound',
        'update': 'update-sound',
        'delete': 'delete-sound'
    };

    const soundId = soundMap[type];
    if (!soundId) return;

    if (currentSound) {
        currentSound.pause();
        currentSound.currentTime = 0;
    }

    const sound = document.getElementById(soundId);
    if (sound) {
        sound.currentTime = 0;
        sound.play().catch(() => {});
        currentSound = sound;

        setTimeout(() => {
            if (currentSound === sound) {
                sound.pause();
                sound.currentTime = 0;
                currentSound = null;
            }
        }, 2000);
    }
}


function showFeedbackIcon(type) {
    if (!feedbackIcon) return;

    const imageMap = {
        'success': 'success.png',
        'error': 'error.png',
        'update': 'update.png',
        'delete': 'delete.png'
    };

    const imageSrc = imageMap[type] || 'error.png';
    feedbackIcon.src = imageSrc;

    feedbackIcon.style.opacity = '1';
    setTimeout(() => {
        feedbackIcon.style.opacity = '0';
    }, 2000);
}


function showModal(message) {
    if (!modalOverlay || !modalText) return;
    modalText.textContent = message;
    modalOverlay.classList.add('show');
}

if (modalCloseBtn && modalOverlay) {
    modalCloseBtn.addEventListener('click', () => {
        modalOverlay.classList.remove('show');
    });

    modalOverlay.addEventListener('click', (e) => {
        if (e.target === modalOverlay) {
            modalOverlay.classList.remove('show');
        }
    });
}

function showDeleteModal(entryId) {
    currentEntryId = entryId;
    if (deleteModal) {
        deleteModal.classList.add('show');
    }
}

function hideDeleteModal() {
    if (deleteModal) {
        deleteModal.classList.remove('show');
    }
    currentEntryId = null;
}

function showEditModal(entryId, name, message) {
    currentEntryId = entryId;
    if (editNameInput) editNameInput.value = name;
    if (editMessageInput) editMessageInput.value = message;
    if (editModal) {
        editModal.classList.add('show');
    }
}

function hideEditModal() {
    if (editModal) {
        editModal.classList.remove('show');
    }
    if (editForm) editForm.reset();
    currentEntryId = null;
}

if (deleteCancelBtn) {
    deleteCancelBtn.addEventListener('click', hideDeleteModal);
}

if (deleteModal) {
    deleteModal.addEventListener('click', (e) => {
        if (e.target === deleteModal) {
            hideDeleteModal();
        }
    });
}

if (deleteConfirmBtn) {
    deleteConfirmBtn.addEventListener('click', async () => {
        if (!currentEntryId) return;

        try {
            await deleteEntry(currentEntryId);
            hideDeleteModal();
            showFeedbackIcon('delete');
            playSound('delete');
            await loadEntries();
            await loadStats();
        } catch (error) {
            hideDeleteModal();
            showFeedbackIcon('error');
            playSound('error');
            showModal('Could not delete log entry.');
        }
    });
}

if (editCancelBtn) {
    editCancelBtn.addEventListener('click', hideEditModal);
}

if (editModal) {
    editModal.addEventListener('click', (e) => {
        if (e.target === editModal) {
            hideEditModal();
        }
    });
}

if (editForm) {
    editForm.addEventListener('submit', async (e) => {
        e.preventDefault();

        if (!currentEntryId) return;

        const name = editNameInput.value.trim();
        const message = editMessageInput.value.trim();

        if (!name || !message) {
            showFeedbackIcon('error');
            playSound('error');
            showModal('Identity and Message Payload cannot be empty.');
            return;
        }

        try {
            await updateEntry(currentEntryId, name, message);
            hideEditModal();
            showFeedbackIcon('update');
            playSound('update');
            await loadEntries();
            await loadStats();
        } catch (error) {
            hideEditModal();
            showFeedbackIcon('error');
            playSound('error');
            showModal('Could not update log entry.');
        }
    });
}


async function loadEntries() {
    try {
        const response = await fetch('/api/entries', {
            cache: 'no-store'
        });
        const cacheHeader = response.headers.get('X-Cache');

        console.log('X-Cache header:', cacheHeader);


        if (cacheStatusEl) {
            if (cacheHeader === 'HIT') {
                cacheStatusEl.innerHTML = 'From cache <span class="cache-tech">(HIT)</span>';
                cacheStatusEl.style.color = '#10b981';
            } else if (cacheHeader === 'MISS') {
                cacheStatusEl.innerHTML = 'From database <span class="cache-tech">(MISS)</span>';
                cacheStatusEl.style.color = '#f59e0b';
            } else {
                cacheStatusEl.textContent = 'N/A';
                cacheStatusEl.style.color = '#6b7280';
            }
        }

        if (cacheTimestampEl) {
            const now = new Date();
            const timeStr = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
            cacheTimestampEl.textContent = timeStr;
        }

        const entries = await response.json();
        const order = sortSelect ? sortSelect.value : 'desc';

        entries.sort((a, b) => {
            const da = new Date(a.created_at);
            const db = new Date(b.created_at);
            return order === 'desc' ? db - da : da - db;
        });

        if (!entries.length) {
            entriesList.innerHTML = '<div class="entry">System log empty. Initialize sequence...</div>';
            return;
        }

        entriesList.innerHTML = entries.map(entry => {
            const date = new Date(entry.created_at);
            const dateStr = date.toLocaleDateString('en-US');
            const timeStr = date.toLocaleTimeString('en-US');
            return `
                <div class="entry" data-id="${entry.id}">
                    <div class="entry-header">
                        <div>
                            <span class="entry-name">${escapeHtml(entry.name)}</span>
                            <span class="entry-date">${dateStr} ${timeStr}</span>
                        </div>
                        <div class="entry-actions">
                            <button class="entry-btn edit-btn" data-id="${entry.id}">Edit</button>
                            <button class="entry-btn delete-btn" data-id="${entry.id}">Purge</button>
                        </div>
                    </div>
                    <div class="entry-message">${escapeHtml(entry.message)}</div>
                </div>
            `;
        }).join('');
    } catch (error) {
        entriesList.innerHTML =
            '<div class="error">Connection Failed. Backend Service Unreachable.</div>';
    }
}


async function loadStats() {
    try {
        const response = await fetch('/api/stats');
        const stats = await response.json();
        if (totalEntriesEl) {
            totalEntriesEl.textContent = stats.total_entries_db || 0;
        }
    } catch (error) {
        if (totalEntriesEl) {
            totalEntriesEl.textContent = '-';
        }
    }
}


async function loadHealth() {
    try {
        const response = await fetch('/health');
        const health = await response.json();

        if (healthStatusEl) {
            if (health.status === 'healthy') {
                healthStatusEl.textContent = '✓';
                healthStatusEl.style.color = '#10b981';
            } else if (health.status === 'degraded') {
                healthStatusEl.textContent = '⚠';
                healthStatusEl.style.color = '#f59e0b';
            } else {
                healthStatusEl.textContent = '✖';
                healthStatusEl.style.color = '#ef4444';
            }
        }
    } catch (error) {
        if (healthStatusEl) {
            healthStatusEl.textContent = '✖';
            healthStatusEl.style.color = '#ef4444';
        }
    }
}


async function createEntry(name, message) {
    const response = await fetch('/api/entries', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ name, message })
    });
    if (!response.ok) {
        throw new Error('Fel vid skapande av inlägg');
    }
}

async function updateEntry(id, name, message) {
    const response = await fetch(`/api/entries/${id}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ name, message })
    });
    if (!response.ok) {
        throw new Error('Fel vid uppdatering');
    }
}

async function deleteEntry(id) {
    const response = await fetch(`/api/entries/${id}`, {
        method: 'DELETE'
    });
    if (!response.ok && response.status !== 204) {
        throw new Error('Fel vid borttagning');
    }
}


if (entryForm) {
    entryForm.addEventListener('submit', async (e) => {
        e.preventDefault();

        const name = nameInput.value.trim();
        const message = messageInput.value.trim();

        if (!name || !message) {
            playSound('error');
            showModal('Identity and Message Payload required.');
            return;
        }

        try {
            await createEntry(name, message);
            entryForm.reset();

            showFeedbackIcon('success');
            playSound('success');

            await loadEntries();
            await loadStats();
        } catch (error) {
            playSound('error');
            showModal('Write Failed. Retrying...');

        }
    });
}


if (entriesList) {
    entriesList.addEventListener('click', async (e) => {
        const btn = e.target.closest('button');
        if (!btn) return;

        const id = btn.dataset.id;
        if (!id) return;

        if (btn.classList.contains('delete-btn')) {
            showDeleteModal(id);
        } else if (btn.classList.contains('edit-btn')) {
            const entryEl = btn.closest('.entry');
            if (!entryEl) return;

            const nameEl = entryEl.querySelector('.entry-name');
            const msgEl = entryEl.querySelector('.entry-message');

            const currentName = nameEl ? nameEl.textContent : '';
            const currentMessage = msgEl ? msgEl.textContent : '';

            showEditModal(id, currentName, currentMessage);
        }
    });
}


if (sortSelect) {
    sortSelect.addEventListener('change', () => {
        loadEntries();
    });
}


loadEntries();
loadStats();
loadHealth();

setInterval(() => {
    loadEntries();
    loadStats();
    loadHealth();
}, 30000);
