import { useState, useEffect } from 'react'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js'
import { Line, Bar, Doughnut } from 'react-chartjs-2'

ChartJS.register(
  CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, ArcElement, Title, Tooltip, Legend,
)

const DARK_BG    = '#1a1d27'
const GRID_COLOR = 'rgba(255,255,255,0.08)'
const MAX_POINTS = 13  // keep 13 data points in the rolling chart

const baseChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { labels: { color: '#a0aec0', boxWidth: 12, font: { size: 11 } } },
    title:  { display: false },
    tooltip: { backgroundColor: '#2d3748', titleColor: '#e2e8f0', bodyColor: '#a0aec0' },
  },
  scales: {
    x: { ticks: { color: '#718096', font: { size: 10 } }, grid: { color: GRID_COLOR } },
    y: { ticks: { color: '#718096', font: { size: 10 } }, grid: { color: GRID_COLOR } },
  },
}

function StatCard({ label, value, color }) {
  return (
    <div className="rounded-lg p-4" style={{ backgroundColor: DARK_BG, border: '1px solid #2d3748' }}>
      <p className="text-xs mb-1" style={{ color: '#718096' }}>{label}</p>
      <p className="text-2xl font-bold" style={{ color }}>{value}</p>
    </div>
  )
}

function ChartCard({ title, children }) {
  return (
    <div className="rounded-lg p-5" style={{ backgroundColor: DARK_BG, border: '1px solid #2d3748' }}>
      <h2 className="text-sm font-semibold mb-4" style={{ color: '#a0aec0' }}>{title}</h2>
      {children}
    </div>
  )
}

export default function ObservabilityTab() {
  const [metrics, setMetrics] = useState(null)

  // Rolling queue depth history for the bar chart
  const [queueHistory, setQueueHistory] = useState({
    labels:   [],
    high: [],
    low:  [],
  })

  const fetchMetrics = async () => {
    try {
      const res = await fetch('/api/metrics')
      if (!res.ok) return
      const data = await res.json()
      setMetrics(data)

      // Append new queue depth snapshot
      const label = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
      setQueueHistory(prev => {
        const labels = [...prev.labels, label].slice(-MAX_POINTS)
        const high   = [...prev.high,   data.high_queue_depth].slice(-MAX_POINTS)
        const low    = [...prev.low,    data.low_queue_depth].slice(-MAX_POINTS)
        return { labels, high, low }
      })
    } catch (_) {}
  }

  useEffect(() => {
    fetchMetrics()
    const id = setInterval(fetchMetrics, 5000)
    return () => clearInterval(id)
  }, [])

  // Build doughnut data from real type counts
  const typeData = metrics ? {
    labels: ['Purchase', 'Withdrawal', 'Transfer', 'Deposit'],
    datasets: [{
      data: [
        metrics.type_counts.purchase,
        metrics.type_counts.withdrawal,
        metrics.type_counts.transfer,
        metrics.type_counts.deposit,
      ],
      backgroundColor: ['#3b82f6', '#ef4444', '#f59e0b', '#22c55e'],
      borderColor: '#1a1d27',
      borderWidth: 2,
    }],
  } : null

  // Build queue depth bar chart from rolling history
  const queueChartData = {
    labels: queueHistory.labels,
    datasets: [
      {
        label: 'High priority',
        data: queueHistory.high,
        backgroundColor: 'rgba(59,130,246,0.7)',
      },
      {
        label: 'Low priority',
        data: queueHistory.low,
        backgroundColor: 'rgba(239,68,68,0.7)',
      },
    ],
  }

  const txPerMin  = metrics?.tx_per_min  ?? '—'
  const errorRate = metrics ? `${metrics.error_rate}%` : '—'
  const total     = metrics?.total ?? 0
  const flagged   = metrics?.flagged ?? 0

  return (
    <div className="space-y-6">
      {/* Stats row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Transactions/min"   value={txPerMin}  color="#e2e8f0" />
        <StatCard label="Total transactions" value={total}     color="#e2e8f0" />
        <StatCard label="Flagged (fraud)"    value={flagged}   color={flagged > 0 ? '#ef4444' : '#22c55e'} />
        <StatCard label="Error rate"         value={errorRate} color={metrics?.error_rate > 1 ? '#ef4444' : '#22c55e'} />
      </div>

      {/* Queue depth over time — real SQS data */}
      <ChartCard title="Queue depth over time (live)">
        <div style={{ height: 240 }}>
          <Bar data={queueChartData} options={baseChartOptions} />
        </div>
      </ChartCard>

      {/* Transaction volume by type — real DynamoDB data */}
      <ChartCard title="Transaction volume by type (live)">
        <div className="flex justify-center" style={{ height: 260 }}>
          {typeData ? (
            <Doughnut
              data={typeData}
              options={{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: {
                    position: 'right',
                    labels: { color: '#a0aec0', boxWidth: 12, font: { size: 11 } },
                  },
                  tooltip: {
                    backgroundColor: '#2d3748',
                    titleColor: '#e2e8f0',
                    bodyColor: '#a0aec0',
                    callbacks: {
                      label: ctx => ` ${ctx.label}: ${ctx.parsed}`,
                    },
                  },
                },
              }}
            />
          ) : (
            <p style={{ color: '#4a5568' }}>Loading...</p>
          )}
        </div>
      </ChartCard>
    </div>
  )
}
