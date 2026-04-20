import { useState, useEffect } from 'react'
import ChaosTab from './components/ChaosTab'
import ObservabilityTab from './components/ObservabilityTab'
import SystemStatusTab from './components/SystemStatusTab'
import TransactionExplorer from './components/TransactionExplorer'
import BatchUpload from './components/BatchUpload'

const TABS = [
  { id: 'chaos',       label: 'Chaos engineering' },
  { id: 'observe',     label: 'Observability' },
  { id: 'system',      label: 'System status' },
  { id: 'transactions',label: 'Transaction explorer' },
  { id: 'batch',       label: 'Batch upload' },
]

const DEFAULT_STATUS = {
  services: [],
  high_dlq_depth: 0,
  low_dlq_depth: 0,
  high_queue_depth: 0,
  low_queue_depth: 0,
  alert_queue_depth: 0,
  alert_dlq_depth: 0,
  events: [],
}

export default function App() {
  const [activeTab, setActiveTab] = useState('chaos')
  const [status, setStatus] = useState(DEFAULT_STATUS)
  const [batchRunning, setBatchRunning] = useState(false)
  const [batchProgress, setBatchProgress] = useState({ sent: 0, total: 0 })

  const fetchStatus = async () => {
    try {
      const res = await fetch('/api/status')
      if (res.ok) {
        const data = await res.json()
        setStatus(data)
      }
    } catch (_) {
      // silently ignore network errors during polling
    }
  }

  useEffect(() => {
    fetchStatus()
    const id = setInterval(fetchStatus, 5000)
    return () => clearInterval(id)
  }, [])

  return (
    <div className="min-h-screen" style={{ backgroundColor: '#0f1117' }}>
      {/* Header */}
      <header style={{ backgroundColor: '#161b27', borderBottom: '1px solid #2d3748' }}>
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-14">
            <div className="flex items-center gap-3">
              <div className="w-7 h-7 rounded" style={{ backgroundColor: '#3b82f6' }}>
                <svg viewBox="0 0 28 28" fill="white" className="w-7 h-7 p-1">
                  <path d="M4 20 L10 12 L16 16 L22 6" stroke="white" strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </div>
              <span className="font-semibold text-white text-sm tracking-wide">
                Trading Risk Monitor
              </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
              {batchRunning && (
                <div
                  onClick={() => setActiveTab('batch')}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 8,
                    background: '#1e3a5f', border: '1px solid #3b82f6',
                    borderRadius: 6, padding: '4px 12px', cursor: 'pointer',
                  }}
                >
                  <span style={{
                    width: 8, height: 8, borderRadius: '50%', background: '#3b82f6',
                    animation: 'pulse 1.2s infinite',
                    display: 'inline-block',
                  }} />
                  <span style={{ color: '#93c5fd', fontSize: 12 }}>
                    Batch running — {batchProgress.sent.toLocaleString()} / {batchProgress.total.toLocaleString()}
                  </span>
                </div>
              )}
              <span className="text-xs" style={{ color: '#4a5568' }}>
                Auto-refresh every 5s
              </span>
            </div>
          </div>

          {/* Tab navigation */}
          <div className="flex gap-1">
            {TABS.map(tab => {
              const active = tab.id === activeTab
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className="px-4 py-3 text-sm font-medium transition-colors focus:outline-none"
                  style={{
                    color: active ? '#ffffff' : '#718096',
                    borderBottom: active ? '2px solid #3b82f6' : '2px solid transparent',
                    background: 'none',
                    cursor: 'pointer',
                  }}
                >
                  {tab.label}
                </button>
              )
            })}
          </div>
        </div>
      </header>

      {/* Tab content — all tabs stay mounted; inactive ones are hidden so
          long-running operations (e.g. BatchUpload SSE stream) survive tab switches */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div style={{ display: activeTab === 'chaos' ? 'block' : 'none' }}>
          <ChaosTab
            services={status.services}
            highDlqDepth={status.high_dlq_depth}
            lowDlqDepth={status.low_dlq_depth}
            highQueueDepth={status.high_queue_depth}
            lowQueueDepth={status.low_queue_depth}
            alertQueueDepth={status.alert_queue_depth}
            alertDlqDepth={status.alert_dlq_depth}
            events={status.events}
            onRefresh={fetchStatus}
          />
        </div>
        <div style={{ display: activeTab === 'observe' ? 'block' : 'none' }}>
          <ObservabilityTab services={status.services} />
        </div>
        <div style={{ display: activeTab === 'system' ? 'block' : 'none' }}>
          <SystemStatusTab services={status.services} />
        </div>
        <div style={{ display: activeTab === 'transactions' ? 'block' : 'none' }}>
          <TransactionExplorer />
        </div>
        <div style={{ display: activeTab === 'batch' ? 'block' : 'none' }}>
          <BatchUpload
            onRunningChange={setBatchRunning}
            onProgressChange={setBatchProgress}
          />
        </div>
      </main>
    </div>
  )
}
