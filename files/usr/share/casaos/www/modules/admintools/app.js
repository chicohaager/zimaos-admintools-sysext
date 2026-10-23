'use strict';
// admintools tile. Helpers (api, esc, $, setStatus, describe, initTheme) come from common.js.

const API = '/admintools';

async function loadTools() {
  const d = await api(`${API}/tools`);
  $('#tools').innerHTML = d.tools.map((t) => `
    <tr>
      <td class="mono">${esc(t.name)}</td>
      <td>${esc(t.description)}</td>
      <td class="mono">${t.version ? esc(t.version) : '<span class="muted">unknown</span>'} <span class="muted">${esc(t.package)}</span></td>
      <td>${t.present ? '<span class="pill pill-ok">installed</span>' : '<span class="pill pill-danger">missing</span>'}</td>
    </tr>`).join('');
  $('#packages').textContent = (d.packages || []).join('\n');
}

async function runSelftest() {
  const btn = $('#selftest-btn');
  btn.disabled = true;
  setStatus('Self-test running …');
  $('#selftest').innerHTML = '<div class="loading">Running every tool once &hellip;</div>';
  try {
    const d = await api(`${API}/selftest`, { method: 'POST', body: {} });
    $('#selftest').innerHTML = `<table><tbody>${d.checks.map((c) => `
      <tr><td>${c.ok ? '<span class="pill pill-ok">OK</span>' : '<span class="pill pill-danger">FAIL</span>'}</td>
      <td class="mono">${esc(c.name)}</td><td class="muted">${esc(c.detail || '')}</td></tr>`).join('')}</tbody></table>`;
    const n = d.checks.length;
    setStatus(d.failed ? `${d.failed} of ${n} checks failed.` : `All ${n} checks passed.`, d.failed ? 'err' : 'ok');
  } catch (e) {
    $('#selftest').innerHTML = '';
    setStatus(describe(e), 'err');
  } finally {
    btn.disabled = false;
  }
}

async function refresh() {
  try {
    await loadTools();
    setStatus('');
  } catch (e) {
    $('#tools').innerHTML = `<tr><td colspan="4" class="app-err">${esc(describe(e))}</td></tr>`;
    setStatus(describe(e), 'err');
  }
}

initTheme('admintools.theme');
$('#refresh-btn').addEventListener('click', refresh);
$('#selftest-btn').addEventListener('click', runSelftest);
refresh();
