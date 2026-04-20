const DARK_BG   = '#1a1d27'
const DARK_CARD = '#1e2230'
const BORDER    = '#2d3748'

function Box({ children, color, borderColor, style = {} }) {
  return (
    <div
      style={{
        backgroundColor: color || DARK_CARD,
        border: `1px solid ${borderColor || BORDER}`,
        borderRadius: 8,
        padding: '6px 14px',
        fontSize: 12,
        fontWeight: 500,
        color: '#e2e8f0',
        textAlign: 'center',
        ...style,
      }}
    >
      {children}
    </div>
  )
}

function LaneLabel({ children }) {
  return (
    <div style={{ textAlign: 'center', color: '#94a3b8', fontSize: 11, fontWeight: 600, letterSpacing: '0.04em' }}>
      {children}
    </div>
  )
}

function Arrow({ direction = 'down' }) {
  const symbols = { down: '↓', left: '↙', right: '↘', split2: '↙  ↘', split3: '↙ ↓ ↘' }
  return (
    <div style={{ textAlign: 'center', color: '#4a5568', fontSize: 16, lineHeight: '1.4', userSelect: 'none' }}>
      {symbols[direction] || '↓'}
    </div>
  )
}

export default function SystemStatusTab({ services }) {
  return (
    <div className="space-y-8">
      {/* ------------------------------------------------------------------ */}
      {/* Architecture diagram                                                 */}
      {/* ------------------------------------------------------------------ */}
      <div
        className="rounded-lg p-6"
        style={{ backgroundColor: DARK_BG, border: `1px solid ${BORDER}` }}
      >
        <h2 className="text-sm font-semibold mb-6" style={{ color: '#a0aec0' }}>
          System architecture
        </h2>

        <div className="space-y-3">

          {/* Trader → ALB → Transaction */}
          <div className="flex justify-center gap-4 items-center flex-wrap">
            <Box color="#0f2027" borderColor="#64748b" style={{ minWidth: 80 }}>Trader</Box>
            <div style={{ color: '#4a5568', fontSize: 13 }}>HTTP POST /transaction →</div>
            <Box color="#0f2027" borderColor="#64748b" style={{ minWidth: 100 }}>ALB</Box>
            <div style={{ color: '#4a5568', fontSize: 13 }}>→</div>
            <Box color="#133023" borderColor="#22c55e" style={{ minWidth: 160 }}>Transaction Service</Box>
          </div>

          {/* Transaction writes */}
          <div className="flex justify-center gap-8 flex-wrap">
            <div className="flex flex-col items-center gap-1">
              <div style={{ color: '#4a5568', fontSize: 11 }}>write</div>
              <Arrow />
              <Box color="#1a2340" borderColor="#6366f1" style={{ minWidth: 130 }}>DynamoDB</Box>
            </div>
            <div className="flex flex-col items-center gap-1">
              <div style={{ color: '#4a5568', fontSize: 11 }}>publish</div>
              <Arrow />
              <Box borderColor="#3b82f6" style={{ minWidth: 200 }}>SNS: transaction-events</Box>
            </div>
          </div>

          {/* SNS fan-out label */}
          <div className="flex justify-center">
            <LaneLabel>fan-out → 5 queues (high/critical filter on fraud · risk · compliance)</LaneLabel>
          </div>

          {/* 5 queues + services */}
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-5">
            {[
              { key: 'fraud',      label: 'fraud-queue',        color: '#3b1d1d', border: '#ef4444', service: 'Fraud Svc',        filter: 'high/critical' },
              { key: 'risk',       label: 'risk-queue',         color: '#3b1d1d', border: '#ef4444', service: 'Risk Svc',         filter: 'high/critical' },
              { key: 'compliance', label: 'compliance-queue',   color: '#3b1d1d', border: '#ef4444', service: 'Compliance Svc',   filter: 'high/critical' },
              { key: 'analytics',  label: 'analytics-queue',    color: '#1a2340', border: '#3b82f6', service: 'Analytics Svc',    filter: 'all' },
              { key: 'audit',      label: 'audit-logging-queue',color: '#1a2340', border: '#3b82f6', service: 'Audit Logging Svc',filter: 'all' },
            ].map(col => (
              <div key={col.key} className="flex flex-col items-center gap-1">
                <LaneLabel>{col.filter}</LaneLabel>
                <Arrow />
                <Box color={col.color} borderColor={col.border} style={{ minWidth: 140, fontSize: 11 }}>{col.label}</Box>
                <Arrow />
                <Box color={col.color} borderColor={col.border} style={{ minWidth: 140, fontSize: 11 }}>{col.service}</Box>
              </div>
            ))}
          </div>

          {/* Service outputs */}
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-5">
            <div className="flex flex-col items-center gap-1">
              <Arrow />
              <LaneLabel>if detected</LaneLabel>
              <Box color="#2a1a1a" borderColor="#f97316" style={{ minWidth: 140, fontSize: 11 }}>SNS: fraud-alert-events</Box>
            </div>
            <div className="flex flex-col items-center gap-1">
              <Arrow />
              <LaneLabel>if breach</LaneLabel>
              <Box color="#2a1a1a" borderColor="#f97316" style={{ minWidth: 140, fontSize: 11 }}>SNS: risk-breach-events</Box>
              <div style={{ color: '#4a5568', fontSize: 10, marginTop: 4 }}>+ Redis INCRBYFLOAT</div>
              <Box color="#1a2340" borderColor="#8b5cf6" style={{ minWidth: 140, fontSize: 10 }}>Redis Primary (us-west-2)</Box>
              <div style={{ color: '#4a5568', fontSize: 10 }}>dual-write ↓</div>
              <Box color="#1a2340" borderColor="#8b5cf6" style={{ minWidth: 140, fontSize: 10 }}>Redis Replica (us-east-1)</Box>
            </div>
            <div className="flex flex-col items-center gap-1">
              <Arrow />
              <LaneLabel>violation</LaneLabel>
              <Box color="#2a1a1a" borderColor="#f97316" style={{ minWidth: 140, fontSize: 11 }}>SNS: compliance-events</Box>
            </div>
            <div className="flex flex-col items-center gap-1">
              <div style={{ height: 20 }} />
              <LaneLabel>reporting only</LaneLabel>
            </div>
            <div className="flex flex-col items-center gap-1">
              <Arrow />
              <Box color="#1b243f" borderColor="#3b82f6" style={{ minWidth: 140, fontSize: 11 }}>S3 (audit logs)</Box>
            </div>
          </div>

          {/* Alert fan-in */}
          <div className="flex justify-center gap-4 items-center flex-wrap">
            <Box color="#2a1a1a" borderColor="#f97316" style={{ minWidth: 140, fontSize: 11 }}>SNS: fraud-alert-events</Box>
            <div style={{ color: '#4a5568', fontSize: 13 }}>+</div>
            <Box color="#2a1a1a" borderColor="#f97316" style={{ minWidth: 140, fontSize: 11 }}>SNS: risk-breach-events</Box>
            <div style={{ color: '#4a5568', fontSize: 13 }}>→</div>
            <Box color="#2a1f0a" borderColor="#f59e0b" style={{ minWidth: 110, fontSize: 11 }}>Alert Queue</Box>
            <div style={{ color: '#4a5568', fontSize: 13 }}>→</div>
            <Box color="#2a1f0a" borderColor="#f59e0b" style={{ minWidth: 100, fontSize: 11 }}>Alert Svc</Box>
          </div>

          {/* DLQs */}
          <div style={{ borderTop: `1px solid ${BORDER}`, paddingTop: 12 }}>
            <LaneLabel>Dead Letter Queues — after 3 retries (5 for analytics/audit)</LaneLabel>
          </div>
          <div className="grid grid-cols-1 gap-2 lg:grid-cols-5">
            {[
              { name: 'Fraud DLQ',      retries: '3' },
              { name: 'Risk DLQ',       retries: '3' },
              { name: 'Compliance DLQ', retries: '3' },
              { name: 'Analytics DLQ',  retries: '5' },
              { name: 'Audit DLQ',      retries: '5' },
            ].map(q => (
              <div key={q.name} className="flex flex-col items-center gap-1">
                <Arrow />
                <Box color="#3b1d1d" borderColor="#dc2626" style={{ minWidth: 130, fontSize: 11 }}>{q.name}</Box>
              </div>
            ))}
          </div>
          <div className="flex justify-center">
            <Box color="#3b1d1d" borderColor="#dc2626" style={{ minWidth: 200 }}>Manual Review Svc (all 5 DLQs)</Box>
          </div>

        </div>
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* Live service health                                                  */}
      {/* ------------------------------------------------------------------ */}
      <div
        className="rounded-lg p-6"
        style={{ backgroundColor: DARK_BG, border: `1px solid ${BORDER}` }}
      >
        <h2 className="text-sm font-semibold mb-4" style={{ color: '#a0aec0' }}>
          Live service health
        </h2>

        {services.length === 0 ? (
          <p className="text-sm" style={{ color: '#4a5568' }}>Loading…</p>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-8 gap-3">
            {services.map(svc => (
              <div
                key={svc.name}
                className="rounded-lg p-3 flex items-center gap-2"
                style={{ backgroundColor: DARK_CARD, border: `1px solid ${BORDER}` }}
              >
                <span
                  className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                  style={{ backgroundColor: svc.healthy ? '#22c55e' : '#ef4444' }}
                />
                <div className="min-w-0">
                  <p className="text-xs font-medium text-white truncate">{svc.display}</p>
                  <p className="text-xs" style={{ color: svc.healthy ? '#22c55e' : '#ef4444' }}>
                    {svc.healthy ? `${svc.running} running` : 'Unhealthy'}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
