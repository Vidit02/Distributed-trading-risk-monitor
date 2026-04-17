import { useState, useEffect } from 'react'
import ChaosTab from './components/ChaosTab'
import ObservabilityTab from './components/ObservabilityTab'
import SystemStatusTab from './components/SystemStatusTab'
import TransactionExplorer from './components/TransactionExplorer'

const TABS = [
  { id: 'chaos',       label: 'Chaos engineering' },
  { id: 'observe',     label: 'Observability' },
  { id: 'system',      label: 'System status' },
  { id: 'transactions',label: 'Transaction explorer' },
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
            <span className="text-xs" style={{ color: '#4a5568' }}>
              Auto-refresh every 5s
            </span>
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

      {/* Tab content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {activeTab === 'chaos' && (
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
        )}
        {activeTab === 'observe' && (
          <ObservabilityTab services={status.services} />
        )}
        {activeTab === 'system' && (
          <SystemStatusTab services={status.services} />
        )}
        {activeTab === 'transactions' && (
          <TransactionExplorer />
        )}
      </main>
    </div>
  )
}
