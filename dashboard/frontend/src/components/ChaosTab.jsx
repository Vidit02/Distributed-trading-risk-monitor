export default function ChaosTab({ services, highDlqDepth, lowDlqDepth, highQueueDepth, lowQueueDepth, events, onRefresh }) {
  const total = services.length
  const healthy = services.filter(s => s.healthy).length

  const callApi = async (url) => {
    try {
      await fetch(url, { method: 'POST' })
      await onRefresh()
    } catch (err) {
      console.error('API call failed:', err)
    }
  }

  const killService    = (name) => callApi(`/api/chaos/kill/${name}`)
  const restartService = (name) => callApi(`/api/chaos/restart/${name}`)
  const toggleDelay    = (name) => callApi(`/api/chaos/delay/${name}`)

  const highBarPct = Math.min(100, (highDlqDepth / 50) * 100)
  const lowBarPct  = Math.min(100, (lowDlqDepth  / 50) * 100)

  return (
    <div className="space-y-6">
      {/* ------------------------------------------------------------------ */}
      {/* Stats row                                                            */}
      {/* ------------------------------------------------------------------ */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Services up */}
        <div className="rounded-lg p-4" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
          <p className="text-xs mb-1" style={{ color: '#718096' }}>Services up</p>
          <p
            className="text-2xl font-bold"
            style={{ color: healthy === total && total > 0 ? '#22c55e' : '#f59e0b' }}
          >
            {healthy} / {total}
          </p>
        </div>

        {/* High-priority DLQ */}
        <div className="rounded-lg p-4" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
          <p className="text-xs mb-1" style={{ color: '#718096' }}>High-priority DLQ</p>
          <p
            className="text-2xl font-bold"
            style={{ color: highDlqDepth > 0 ? '#ef4444' : '#e2e8f0' }}
          >
            {highDlqDepth}
          </p>
        </div>

        {/* Low-priority DLQ */}
        <div className="rounded-lg p-4" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
          <p className="text-xs mb-1" style={{ color: '#718096' }}>Low-priority DLQ</p>
          <p
            className="text-2xl font-bold"
            style={{ color: lowDlqDepth > 0 ? '#ef4444' : '#e2e8f0' }}
          >
            {lowDlqDepth}
          </p>
        </div>

        {/* Chaos events */}
        <div className="rounded-lg p-4" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
          <p className="text-xs mb-1" style={{ color: '#718096' }}>Chaos events</p>
          <p className="text-2xl font-bold text-white">{events.length}</p>
        </div>
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* Services grid                                                        */}
      {/* ------------------------------------------------------------------ */}
      <div>
        <h2 className="text-sm font-semibold mb-3" style={{ color: '#a0aec0' }}>Services</h2>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {services.map(svc => (
            <div
              key={svc.name}
              className="rounded-lg p-4 flex flex-col gap-2"
              style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}
            >
              {/* Name row */}
              <div className="flex items-center gap-2">
                <span
                  className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                  style={{ backgroundColor: svc.healthy ? '#22c55e' : '#ef4444' }}
                />
                <span className="font-semibold text-white text-sm truncate">{svc.display}</span>
              </div>

              {/* Health status */}
              <p className="text-xs" style={{ color: svc.healthy ? '#22c55e' : '#ef4444' }}>
                {svc.healthy ? 'Healthy' : 'Unhealthy'}
              </p>

              {/* Queue badge */}
              {svc.queue && (
                <span
                  className="text-xs px-2 py-0.5 rounded-full w-fit"
                  style={{ backgroundColor: '#2d3748', color: '#a0aec0' }}
                >
                  Queue: {svc.queue}
                </span>
              )}

              {/* Delay badge */}
              {svc.delayed && (
                <span
                  className="text-xs px-2 py-0.5 rounded-full w-fit font-medium"
                  style={{ backgroundColor: '#78350f', color: '#fbbf24' }}
                >
                  ⚡ 3s delay
                </span>
              )}

              {/* Buttons */}
              <div className="flex flex-wrap gap-2 mt-1">
                {svc.healthy ? (
                  <button
                    onClick={() => killService(svc.name)}
                    className="text-xs px-3 py-1 rounded font-medium transition-opacity hover:opacity-80"
                    style={{ backgroundColor: '#7f1d1d', color: '#fca5a5' }}
                  >
                    Kill
                  </button>
                ) : (
                  <button
                    onClick={() => restartService(svc.name)}
                    className="text-xs px-3 py-1 rounded font-medium transition-opacity hover:opacity-80"
                    style={{ backgroundColor: '#14532d', color: '#86efac' }}
                  >
                    Restart
                  </button>
                )}

                {svc.queue && (
                  <button
                    onClick={() => toggleDelay(svc.name)}
                    className="text-xs px-3 py-1 rounded font-medium transition-opacity hover:opacity-80"
                    style={{ backgroundColor: '#374151', color: '#d1d5db' }}
                  >
                    {svc.delayed ? 'Remove delay' : 'Add delay'}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* DLQ depth                                                            */}
      {/* ------------------------------------------------------------------ */}
      <div className="rounded-lg p-5" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
        <h2 className="text-sm font-semibold mb-4" style={{ color: '#a0aec0' }}>Queue depth</h2>

        {[
          { label: 'High queue', value: highQueueDepth, color: '#3b82f6' },
          { label: 'Low queue',  value: lowQueueDepth,  color: '#8b5cf6' },
          { label: 'High DLQ',  value: highDlqDepth,   color: '#ef4444' },
          { label: 'Low DLQ',   value: lowDlqDepth,    color: '#f59e0b' },
        ].map(({ label, value, color }) => (
          <div key={label} className="flex items-center gap-3 mb-3">
            <span className="text-xs w-24 flex-shrink-0" style={{ color: '#a0aec0' }}>{label}</span>
            <div className="flex-1 rounded-full h-2" style={{ backgroundColor: '#2d3748' }}>
              <div
                className="h-2 rounded-full transition-all duration-500"
                style={{ width: `${Math.min(100, (value / 50) * 100)}%`, backgroundColor: color }}
              />
            </div>
            <span className="text-xs w-8 text-right font-medium" style={{ color: '#e2e8f0' }}>
              {value}
            </span>
          </div>
        ))}
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* Event log                                                            */}
      {/* ------------------------------------------------------------------ */}
      <div className="rounded-lg p-5" style={{ backgroundColor: '#1a1d27', border: '1px solid #2d3748' }}>
        <h2 className="text-sm font-semibold mb-3" style={{ color: '#a0aec0' }}>Event log</h2>
        <div
          className="rounded p-3 font-mono text-xs leading-relaxed overflow-y-auto"
          style={{
            backgroundColor: '#0d1117',
            color: '#22c55e',
            minHeight: '120px',
            maxHeight: '240px',
          }}
        >
          {events.length === 0 ? (
            <span style={{ color: '#22c55e' }}>Dashboard initialized — all services healthy</span>
          ) : (
            events.map((ev, i) => (
              <div key={i}>
                [{ev.time}] {ev.message}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}
