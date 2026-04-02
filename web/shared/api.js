/**
 * Fabio Shared API Client & Utilities
 * ====================================
 * Shared JavaScript utilities for all web portals.
 */

// ── Configuration ─────────────────────────────────────────────────────────────
const API_BASE = window.location.origin;

// ── Session Management ────────────────────────────────────────────────────────
function getToken() {
    return localStorage.getItem('fabio_session_token');
}

function setToken(token) {
    localStorage.setItem('fabio_session_token', token);
}

function clearToken() {
    localStorage.removeItem('fabio_session_token');
    localStorage.removeItem('fabio_user');
}

function getUser() {
    try {
        return JSON.parse(localStorage.getItem('fabio_user'));
    } catch { return null; }
}

function setUser(user) {
    localStorage.setItem('fabio_user', JSON.stringify(user));
}

// ── API Client ────────────────────────────────────────────────────────────────
async function api(endpoint, options = {}) {
    const token = getToken();
    const headers = {
        'Content-Type': 'application/json',
        ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
        ...options.headers,
    };

    try {
        const response = await fetch(`${API_BASE}${endpoint}`, {
            ...options,
            headers,
        });

        if (response.status === 401) {
            clearToken();
            window.location.href = window.location.pathname.split('/')[1]
                ? `/${window.location.pathname.split('/')[1]}/`
                : '/';
            return null;
        }

        const data = response.status === 204 ? null : await response.json();

        if (!response.ok) {
            throw new Error(data?.detail || `HTTP ${response.status}`);
        }

        return data;
    } catch (error) {
        if (error.message.includes('Failed to fetch')) {
            showToast('Network error — check your connection', 'error');
        }
        throw error;
    }
}

// Convenience methods
const GET = (url) => api(url);
const POST = (url, body) => api(url, { method: 'POST', body: JSON.stringify(body) });
const PATCH = (url, body) => api(url, { method: 'PATCH', body: JSON.stringify(body) });
const DELETE = (url) => api(url, { method: 'DELETE' });

// ── Toast Notifications ───────────────────────────────────────────────────────
function ensureToastContainer() {
    let container = document.querySelector('.toast-container');
    if (!container) {
        container = document.createElement('div');
        container.className = 'toast-container';
        document.body.appendChild(container);
    }
    return container;
}

function showToast(message, type = 'info', duration = 4000) {
    const container = ensureToastContainer();
    const icons = { success: '✓', error: '✕', info: 'ℹ', warning: '⚠' };
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `<span>${icons[type] || 'ℹ'}</span><span>${message}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('hiding');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function formatDate(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    return d.toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric',
        hour: '2-digit', minute: '2-digit',
    });
}

function formatCurrency(amount, currency = 'INR') {
    return new Intl.NumberFormat('en-IN', {
        style: 'currency',
        currency: currency,
    }).format(amount);
}

function getRoleBadge(role) {
    const map = {
        admin: '<span class="badge badge-admin">Admin</span>',
        vice_admin: '<span class="badge badge-vice">Vice Admin</span>',
        user: '<span class="badge badge-default">User</span>',
    };
    return map[role] || `<span class="badge badge-default">${role}</span>`;
}

function getStatusBadge(isActive) {
    return isActive
        ? '<span class="badge badge-success">Active</span>'
        : '<span class="badge badge-danger">Inactive</span>';
}

function getTxnStatusBadge(status) {
    const map = {
        success: '<span class="badge badge-success">Success</span>',
        failed: '<span class="badge badge-danger">Failed</span>',
        pending: '<span class="badge badge-warning">Pending</span>',
    };
    return map[status] || `<span class="badge badge-default">${status}</span>`;
}

function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function getUserInitials(name) {
    if (!name) return '?';
    return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
}

// ── Google Sign-In ────────────────────────────────────────────────────────────
function initGoogleSignIn(callback) {
    // Load Google Identity Services script
    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.async = true;
    script.defer = true;
    script.onload = () => {
        // Google client will be initialized when needed
        window._googleSignInCallback = callback;
    };
    document.head.appendChild(script);
}

function renderGoogleButton(containerId) {
    if (typeof google !== 'undefined' && google.accounts) {
        google.accounts.id.initialize({
            client_id: window._googleClientId || '',
            callback: window._googleSignInCallback,
        });
        google.accounts.id.renderButton(
            document.getElementById(containerId),
            { theme: 'filled_black', size: 'large', width: '100%', shape: 'rectangular' }
        );
    }
}

// ── Loading States ────────────────────────────────────────────────────────────
function showLoading() {
    let overlay = document.querySelector('.loading-overlay');
    if (!overlay) {
        overlay = document.createElement('div');
        overlay.className = 'loading-overlay';
        overlay.innerHTML = '<div class="spinner"></div><div class="loading-text">Loading...</div>';
        document.body.appendChild(overlay);
    }
    overlay.style.display = 'flex';
}

function hideLoading() {
    const overlay = document.querySelector('.loading-overlay');
    if (overlay) overlay.style.display = 'none';
}

// ── Modal Utilities ───────────────────────────────────────────────────────────
function openModal(id) {
    document.getElementById(id)?.classList.add('active');
}

function closeModal(id) {
    document.getElementById(id)?.classList.remove('active');
}

// ── Navigation ────────────────────────────────────────────────────────────────
function setActiveNav(pageId) {
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.toggle('active', item.dataset.page === pageId);
    });
}

function showPage(pageId) {
    document.querySelectorAll('.page').forEach(page => {
        page.style.display = page.id === `page-${pageId}` ? 'block' : 'none';
    });
    setActiveNav(pageId);
}
