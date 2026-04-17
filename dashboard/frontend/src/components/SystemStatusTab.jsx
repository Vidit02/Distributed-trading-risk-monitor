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

        {/* Row 1: Ingress */}
        <div className="flex justify-center gap-3 mb-1">
          <Box color="#1a2e1a" borderColor="#22c55e" style={{ minWidth: 80 }}>ALB</Box>
          <Box color="#1a2e1a" borderColor="#22c55e" style={{ minWidth: 160 }}>Transaction service</Box>
        </div>

        <Arrow />

        {/* Row 2: transaction-events SNS */}
        <div className="flex justify-center mb-1">
          <Box borderColor="#3b82f6" style={{ minWidth: 220 }}>SNS: transaction-events</Box>
        </div>

        <Arrow direction="split2" />

        {/* Row 3: two main queues */}
        <div className="flex justify-center gap-12 mb-1">
          <Box color="#2a1a1a" borderColor="#ef4444" style={{ minWidth: 160 }}>High-priority SQS</Box>
          <Box color="#1a1a2e" borderColor="#3b82f6" style={{ minWidth: 160 }}>Low-priority SQS</Box>
        </div>

        {/* Row 4: consumers of the two main queues */}
        <div className="flex justify-center gap-12 mb-1">
          {/* High priority consumers */}
          <div className="flex flex-col items-center gap-1" style={{ minWidth: 160 }}>
            <Arrow />
            <div className="flex flex-col gap-1 w-full">
              <Box color="#2a1a1a" borderColor="#ef4444">Fraud detection</Box>
              <Box color="#2a1a1a" borderColor="#ef4444">Risk monitor</Box>
              <Box color="#2a1a1a" borderColor="#ef4444">Compliance</Box>
            </div>
          </div>

          {/* Low priority consumers */}
          <div className="flex flex-col items-center gap-1" style={{ minWidth: 160 }}>
            <Arrow />
            <div className="flex flex-col gap-1 w-full">
              <Box color="#1a1a2e" borderColor="#3b82f6">Analytics</Box>
              <Box color="#1a1a2e" borderColor="#3b82f6">Audit logging</Box>
            </div>
          </div>
        </div>

        {/* Row 5: fraud + risk publish alert SNS topics */}
        <div className="flex justify-center mb-1 mt-2">
          <div style={{ textAlign: 'center', color: '#4a5568', fontSize: 12, fontStyle: 'italic' }}>
            fraud &amp; risk publish alerts
          </div>
        </div>

        <Arrow />

        {/* Row 6: alert SNS topics */}
        <div className="flex justify-center gap-3 mb-1">
          <Box borderColor="#f59e0b" style={{ minWidth: 200 }}>SNS: fraud-alert-events</Box>
          <Box borderColor="#f59e0b" style={{ minWidth: 200 }}>SNS: risk-breach-events</Box>
        </div>

        <Arrow />

        {/* Row 7: alert SQS */}
        <div className="flex justify-center mb-1">
          <Box color="#2a1f0a" borderColor="#f59e0b" style={{ minWidth: 160 }}>Alert SQS</Box>
        </div>

        <Arrow />

        {/* Row 8: alert service */}
        <div className="flex justify-center mb-1">
          <Box color="#2a1f0a" borderColor="#f59e0b" style={{ minWidth: 160 }}>Alert service</Box>
        </div>

        <div style={{ textAlign: 'center', color: '#4a5568', fontSize: 12, fontStyle: 'italic', margin: '2px 0' }}>
          failed messages → DLQ
        </div>

        <Arrow />

        {/* Row 9: High-priority DLQ → Manual review */}
        <div className="flex justify-center gap-3 mb-1">
          <Box color="#2a1a1a" borderColor="#dc2626" style={{ minWidth: 160 }}>High-priority DLQ</Box>
        </div>

        <Arrow />

        <div className="flex justify-center mb-1">
          <Box color="#2a1a1a" borderColor="#dc2626" style={{ minWidth: 160 }}>Manual review</Box>
        </div>

        <Arrow />

        {/* Row 10: Data stores */}
        <div className="flex justify-center gap-2 flex-wrap mt-1">
          {['DynamoDB', 'Redis', 'S3', 'CloudWatch'].map(name => (
            <Box key={name} color="#1f2210" borderColor="#84cc16" style={{ minWidth: 90 }}>
              {name}
            </Box>
          ))}
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
