import { useEffect, useRef, useState } from 'react'

const CARD = { backgroundColor: '#161b27', border: '1px solid #2d3748', borderRadius: 8, padding: 20 }
const LABEL = { color: '#718096', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 8 }
const MUTED = { color: '#718096' }

const PRI_COLOR = { critical: '#f85149', high: '#d29922', medium: '#3b82f6', low: '#3fb950' }
const TYPE_COLOR = { purchase: '#3b82f6', withdrawal: '#f85149', transfer: '#bc8cff', deposit: '#3fb950' }

function Badge({ children, color }) {
  return (
    <span style={{
      background: color + '22', color, border: `1px solid ${color}55`,
      borderRadius: 4, padding: '1px 8px', fontSize: 11, fontWeight: 600,
    }}>{children}</span>
  )
}

function StatBox({ label, value, color }) {
  return (
    <div style={{ ...CARD, textAlign: 'center', padding: '16px 8px' }}>
      <div style={{ fontSize: 30, fontWeight: 700, color: color || '#e2e8f0' }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </div>
      <div style={{ ...MUTED, fontSize: 11, marginTop: 4 }}>{label}</div>
    </div>
  )
}

export default function BatchUpload({ onRunningChange, onProgressChange }) {
  const [dragOver, setDragOver]     = useState(false)
  const [parsed, setParsed]         = useState(null)   // { session_id, count, preview }
  const [running, setRunning]       = useState(false)
  const [done, setDone]             = useState(false)
  const [progress, setProgress]     = useState({ success: 0, failed: 0, index: 0, tps: 0 })
  const [log, setLog]               = useState([])     // last N SSE progress events
  const [summary, setSummary]       = useState(null)   // final done event
  const [error, setError]           = useState('')
  const fileRef                     = useRef()
  const esRef                       = useRef(null)
  const LOG_LIMIT                   = 200

  // ── file handling ──────────────────────────────────────────────────────────

  async function handleFile(file) {
    setError('')
    setParsed(null)
    setDone(false)
    setLog([])
    setSummary(null)
    setProgress({ success: 0, failed: 0, index: 0, tps: 0 })

    const form = new FormData()
    form.append('file', file)
    try {
      const res = await fetch('/api/upload', { method: 'POST', body: form })
      const data = await res.json()
      if (!res.ok) { setError(data.detail || 'Upload failed'); return }
      setParsed({ ...data, filename: file.name })
    } catch (e) {
      setError(`Upload error: ${e.message}`)
    }
  }

  function onDrop(e) {
    e.preventDefault(); setDragOver(false)
    const f = e.dataTransfer.files[0]
    if (f) handleFile(f)
  }

  function onFileChange(e) {
    const f = e.target.files[0]
    if (f) handleFile(f)
    e.target.value = ''
  }

  // ── submit ─────────────────────────────────────────────────────────────────

  function startSubmit() {
    if (!parsed || running) return
    setRunning(true); setDone(false); setLog([]); setSummary(null)
    setProgress({ success: 0, failed: 0, index: 0, tps: 0 })
    onRunningChange?.(true)
    onProgressChange?.({ sent: 0, total: parsed.count })

    const es = new EventSource(`/api/batch-submit/${parsed.session_id}`)
    esRef.current = es

    es.onmessage = (e) => {
      const ev = JSON.parse(e.data)
      if (ev.type === 'start') return

      if (ev.type === 'done') {
        setSummary(ev)
        setRunning(false); setDone(true)
        onRunningChange?.(false)
        es.close(); esRef.current = null
        return
      }

      // progress
      setProgress({ success: ev.success, failed: ev.failed, index: ev.index + 1, tps: ev.tps })
      onProgressChange?.({ sent: ev.index + 1, total: ev.total })
      setLog(prev => {
        const entry = {
          id:     ev.transaction_id || '—',
          user:   ev.user_id,
          amount: ev.amount,
          ok:     ev.ok,
          status: ev.status,
          error:  ev.error,
          seq:    ev.index + 1,
        }
        const next = [entry, ...prev]
        return next.length > LOG_LIMIT ? next.slice(0, LOG_LIMIT) : next
      })
    }

    es.onerror = () => {
      setError('Connection to server lost. The run may still be completing.')
      setRunning(false)
      onRunningChange?.(false)
      es.close(); esRef.current = null
    }
  }

  function stopSubmit() {
    if (esRef.current) { esRef.current.close(); esRef.current = null }
    setRunning(false)
  }

  function reset() {
    stopSubmit()
    setParsed(null); setDone(false); setLog([]); setSummary(null); setError('')
    setProgress({ success: 0, failed: 0, index: 0, tps: 0 })
  }

  function downloadLog() {
    const header = 'seq,transaction_id,user_id,amount,status,ok\n'
    const rows = [...log].reverse().map(r =>
      `${r.seq},"${r.id}","${r.user}",${r.amount},${r.status},${r.ok}`
    )
    const blob = new Blob([header + rows.join('\n')], { type: 'text/csv' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `batch-results-${Date.now()}.csv`
    a.click()
  }

  // ── derived ────────────────────────────────────────────────────────────────

  const total   = parsed?.count ?? 0
  const sent    = progress.index
  const pct     = total > 0 ? Math.min(100, (sent / total) * 100) : 0

  // ── render ─────────────────────────────────────────────────────────────────

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

      {/* ── Drop zone ── */}
      {!parsed && (
        <div style={CARD}>
          <div style={LABEL}>Upload Transaction File</div>
          <div
            onClick={() => fileRef.current.click()}
            onDragOver={e => { e.preventDefault(); setDragOver(true) }}
            onDragLeave={() => setDragOver(false)}
            onDrop={onDrop}
            style={{
              border: `2px dashed ${dragOver ? '#3b82f6' : '#2d3748'}`,
              borderRadius: 8, padding: '48px 24px', textAlign: 'center',
              cursor: 'pointer', background: dragOver ? '#1e293b' : 'transparent',
              transition: 'border-color 0.2s, background 0.2s',
            }}
          >
            <div style={{ fontSize: 40, marginBottom: 12 }}>📂</div>
            <div style={{ color: '#e2e8f0', fontSize: 14, marginBottom: 6 }}>
              Drop your <strong>Excel (.xlsx)</strong> or <strong>CSV</strong> file here
            </div>
            <div style={{ ...MUTED, fontSize: 12 }}>
              Required columns: user_id · amount · currency · merchant_id · transaction_type
              <br />Optional: priority (low / medium / high / critical)
            </div>
            <button style={{
              marginTop: 16, padding: '8px 20px', borderRadius: 6, border: 'none',
              background: '#3b82f6', color: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer',
            }}>Browse file</button>
          </div>
          <input ref={fileRef} type="file" accept=".xlsx,.xls,.csv" style={{ display: 'none' }} onChange={onFileChange} />

          {/* sample template download */}
          <div style={{ marginTop: 12, display: 'flex', gap: 8 }}>
            <a
              href="/sample-transactions.xlsx"
              download="sample-transactions.xlsx"
              style={{
                display: 'inline-block', padding: '6px 14px', borderRadius: 6,
                border: '1px solid #2d3748', background: 'transparent',
                color: '#718096', fontSize: 12, textDecoration: 'none', cursor: 'pointer',
              }}
            >⬇ Download sample template (.xlsx)</a>
          </div>
        </div>
      )}

      {/* ── Error ── */}
      {error && (
        <div style={{ background: '#f8514922', border: '1px solid #f8514966', borderRadius: 6, padding: '10px 16px', color: '#f85149', fontSize: 13 }}>
          ⚠ {error}
        </div>
      )}

      {/* ── Preview + controls ── */}
      {parsed && (
        <>
          <div style={CARD}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <div>
                <div style={LABEL}>File Loaded</div>
                <div style={{ color: '#e2e8f0', fontSize: 14 }}>
                  <strong>{parsed.filename}</strong>
                  <span style={{ ...MUTED, marginLeft: 10, fontSize: 12 }}>
                    {parsed.count.toLocaleString()} transactions ready to submit
                  </span>
                </div>
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                {!running && !done && (
                  <button onClick={startSubmit} style={{
                    padding: '8px 20px', borderRadius: 6, border: 'none',
                    background: '#3fb950', color: '#000', fontSize: 13, fontWeight: 700, cursor: 'pointer',
                  }}>▶ Submit {parsed.count.toLocaleString()} Transactions</button>
                )}
                {running && (
                  <button onClick={stopSubmit} style={{
                    padding: '8px 20px', borderRadius: 6, border: 'none',
                    background: '#f85149', color: '#fff', fontSize: 13, fontWeight: 700, cursor: 'pointer',
                  }}>■ Stop</button>
                )}
                <button onClick={reset} style={{
                  padding: '8px 16px', borderRadius: 6, border: '1px solid #2d3748',
                  background: 'transparent', color: '#718096', fontSize: 13, cursor: 'pointer',
                }}>✕ Clear</button>
              </div>
            </div>

            {/* preview table */}
            <div style={LABEL}>Preview — first {parsed.preview.length} rows</div>
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid #2d3748' }}>
                    {['#', 'user_id', 'amount', 'currency', 'merchant_id', 'transaction_type', 'priority'].map(h => (
                      <th key={h} style={{ ...MUTED, padding: '6px 10px', textAlign: 'left', fontWeight: 'normal', whiteSpace: 'nowrap' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {parsed.preview.map((row, i) => {
                    const pri = row.priority || 'low'
                    return (
                      <tr key={i} style={{ borderBottom: '1px solid #1e293b' }}>
                        <td style={{ ...MUTED, padding: '5px 10px' }}>{i + 1}</td>
                        <td style={{ padding: '5px 10px', color: '#e2e8f0' }}>{row.user_id}</td>
                        <td style={{ padding: '5px 10px', color: '#e2e8f0' }}>${Number(row.amount).toFixed(2)}</td>
                        <td style={{ padding: '5px 10px', color: '#e2e8f0' }}>{row.currency}</td>
                        <td style={{ padding: '5px 10px', color: '#e2e8f0' }}>{row.merchant_id}</td>
                        <td style={{ padding: '5px 10px', color: '#e2e8f0' }}>{row.transaction_type}</td>
                        <td style={{ padding: '5px 10px' }}>
                          <Badge color={PRI_COLOR[pri] || '#718096'}>{pri.toUpperCase()}</Badge>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
              {parsed.count > parsed.preview.length && (
                <div style={{ ...MUTED, fontSize: 11, marginTop: 6, paddingLeft: 10 }}>
                  … and {(parsed.count - parsed.preview.length).toLocaleString()} more rows
                </div>
              )}
            </div>
          </div>

          {/* ── Progress ── */}
          {(running || done || sent > 0) && (
            <>
              {/* stat boxes */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
                <StatBox label="Total"   value={total}            color="#e2e8f0" />
                <StatBox label="Sent"    value={sent}             color="#3b82f6" />
                <StatBox label="Success" value={progress.success} color="#3fb950" />
                <StatBox label="Failed"  value={progress.failed}  color="#f85149" />
              </div>

              {/* progress bar */}
              <div style={CARD}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                  <div style={{ ...MUTED, fontSize: 12 }}>
                    {sent.toLocaleString()} / {total.toLocaleString()}
                    {running && progress.tps > 0 && (
                      <span style={{ marginLeft: 12 }}>
                        {progress.tps} tx/s
                        {progress.tps > 0 && total > sent && (
                          <span style={{ marginLeft: 8 }}>
                            ETA ~{Math.ceil((total - sent) / progress.tps)}s
                          </span>
                        )}
                      </span>
                    )}
                  </div>
                  <div style={{ ...MUTED, fontSize: 12 }}>{pct.toFixed(1)}%</div>
                </div>
                <div style={{ background: '#0f1117', borderRadius: 4, height: 10, overflow: 'hidden' }}>
                  <div style={{
                    height: '100%', borderRadius: 4,
                    background: done
                      ? (progress.failed === 0 ? '#3fb950' : '#d29922')
                      : 'linear-gradient(90deg, #3b82f6, #bc8cff)',
                    width: `${pct}%`, transition: 'width 0.3s ease',
                  }} />
                </div>
                {done && summary && (
                  <div style={{ marginTop: 10, color: progress.failed === 0 ? '#3fb950' : '#d29922', fontSize: 13, fontWeight: 600 }}>
                    {progress.failed === 0
                      ? `✓ All ${summary.success.toLocaleString()} transactions submitted successfully in ${summary.elapsed}s`
                      : `⚠ Done — ${summary.success.toLocaleString()} succeeded, ${summary.failed.toLocaleString()} failed in ${summary.elapsed}s`
                    }
                  </div>
                )}
              </div>

              {/* live log */}
              <div style={CARD}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                  <div style={LABEL}>Live Transaction Log</div>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <span style={{ ...MUTED, fontSize: 11 }}>{log.length.toLocaleString()} entries (newest first)</span>
                    {log.length > 0 && (
                      <button onClick={downloadLog} style={{
                        padding: '4px 12px', borderRadius: 5, border: '1px solid #2d3748',
                        background: 'transparent', color: '#718096', fontSize: 11, cursor: 'pointer',
                      }}>⬇ Export CSV</button>
                    )}
                  </div>
                </div>
                <div style={{
                  background: '#0f1117', borderRadius: 6, height: 260,
                  overflowY: 'auto', padding: 8, fontFamily: 'monospace', fontSize: 11,
                }}>
                  {log.length === 0
                    ? <span style={MUTED}>Waiting for transactions…</span>
                    : log.map((entry, i) => (
                      <div key={i} style={{ padding: '2px 4px', color: entry.ok ? '#3fb950' : '#f85149', marginBottom: 1 }}>
                        {entry.ok ? '✓' : '✗'}
                        {'  '}
                        <span style={MUTED}>#{entry.seq}</span>
                        {'  '}
                        {entry.user}
                        {'  '}
                        ${Number(entry.amount).toFixed(2)}
                        {'  '}
                        {entry.ok
                          ? <span style={{ color: '#718096' }}>{entry.id.slice(0, 8)}…</span>
                          : <span style={{ color: '#f85149' }}>HTTP {entry.status} {entry.error}</span>
                        }
                      </div>
                    ))
                  }
                </div>
              </div>
            </>
          )}
        </>
      )}
    </div>
  )
}
