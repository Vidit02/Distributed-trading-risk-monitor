const DARK_BG   = '#1a1d27'
const DARK_CARD = '#1e2230'
const BORDER    = '#2d3748'

function Box({ children, color, className = '', style = {} }) {
  const base = {
    backgroundColor: color || DARK_CARD,
    border: `1px solid ${BORDER}`,
    borderRadius: 8,
    padding: '8px 16px',
    fontSize: 13,
    fontWeight: 500,
    color: '#e2e8f0',
    textAlign: 'center',
    ...style,
  }
  return (
    <div style={base} className={className}>
      {children}
    </div>
  )
}

function Arrow({ direction = 'down' }) {
  const symbols = { down: '↓', left: '↙', right: '↘' }
  return (
    <div
      style={{
        textAlign: 'center',
        color: '#4a5568',
        fontSize: 18,
        lineHeight: '1.4',
        userSelect: 'none',
      }}
    >
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

        {/* Ingress row */}
        <div className="flex justify-center gap-4 mb-1">
          <Box color="#1a2e1a" style={{ borderColor: '#22c55e', minWidth: 120 }}>
            ALB
          </Box>
          <Box color="#1a2e1a" style={{ borderColor: '#22c55e', minWidth: 160 }}>
            Transaction service
          </Box>
        </div>

        <Arrow />

        {/* SNS */}
        <div className="flex justify-center mb-1">
          <Box style={{ minWidth: 220, borderColor: '#3b82f6' }}>
            SNS: transaction-events
          </Box>
        </div>

        {/* Branching arrows */}
        <div className="flex justify-center gap-24 mb-1">
          <Arrow direction="left" />
          <Arrow direction="right" />
        </div>

        {/* Two queue columns */}
        <div className="flex justify-center gap-12">
          {/* Left – High priority */}
          <div className="flex flex-col items-center gap-2" style={{ minWidth: 180 }}>
            <Box color="#2a1a1a" style={{ borderColor: '#ef4444', width: '100%' }}>
              High-priority SQS
            </Box>
            <Arrow />
            <div className="flex flex-col gap-2 w-full">
              <Box color="#2a1a1a" style={{ borderColor: '#ef4444' }}>
                Fraud detection
              </Box>
              <Box color="#2a1a1a" style={{ borderColor: '#ef4444' }}>
                Risk monitor
              </Box>
            </div>
          </div>

          {/* Right – Low priority */}
          <div className="flex flex-col items-center gap-2" style={{ minWidth: 180 }}>
            <Box color="#1a1a2e" style={{ borderColor: '#3b82f6', width: '100%' }}>
              Low-priority SQS
            </Box>
            <Arrow />
            <div className="flex flex-col gap-2 w-full">
              <Box color="#1a1a2e" style={{ borderColor: '#3b82f6' }}>
                Analytics
              </Box>
              <Box color="#1a1a2e" style={{ borderColor: '#3b82f6' }}>
                Audit logging
              </Box>
            </div>
          </div>
        </div>

        <Arrow />

        {/* Data stores */}
        <div className="flex justify-center gap-3 flex-wrap">
          {['DynamoDB', 'Redis', 'S3', 'CloudWatch'].map(name => (
            <Box
              key={name}
              color="#1f2210"
              style={{ borderColor: '#84cc16', minWidth: 100 }}
            >
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
          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
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
                  <p
                    className="text-xs"
                    style={{ color: svc.healthy ? '#22c55e' : '#ef4444' }}
                  >
                    {svc.healthy ? 'Healthy' : 'Unhealthy'}
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
