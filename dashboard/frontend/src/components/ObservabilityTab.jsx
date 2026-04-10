import { useState, useEffect, useRef } from 'react'
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
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
)

const rand = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min
const randFloat = (min, max, dec = 1) => parseFloat((Math.random() * (max - min) + min).toFixed(dec))

const LABELS_13 = Array.from({ length: 13 }, (_, i) => `${i * 5}s`)

const makeLatencyData = () => ({
  labels: [...LABELS_13],
  datasets: [
    {
      label: 'High priority',
      data: Array.from({ length: 13 }, () => rand(40, 80)),
      borderColor: '#3b82f6',
      backgroundColor: 'rgba(59,130,246,0.15)',
      tension: 0.4,
      pointRadius: 3,
    },
    {
      label: 'Low priority',
      data: Array.from({ length: 13 }, () => rand(1800, 2500)),
      borderColor: '#ef4444',
      backgroundColor: 'rgba(239,68,68,0.15)',
      tension: 0.4,
      pointRadius: 3,
    },
  ],
})

const makeQueueData = () => ({
  labels: [...LABELS_13],
  datasets: [
    {
      label: 'High priority',
      data: Array.from({ length: 13 }, () => rand(0, 40)),
      backgroundColor: 'rgba(59,130,246,0.7)',
    },
    {
      label: 'Low priority',
      data: Array.from({ length: 13 }, () => rand(0, 20)),
      backgroundColor: 'rgba(239,68,68,0.7)',
    },
  ],
})

const doughnutData = {
  labels: ['Purchase', 'Withdrawal', 'Transfer', 'Deposit'],
  datasets: [
    {
      data: [45, 25, 20, 10],
      backgroundColor: ['#3b82f6', '#ef4444', '#f59e0b', '#22c55e'],
      borderColor: '#1a1d27',
      borderWidth: 2,
    },
  ],
}

const DARK_BG = '#1a1d27'
const GRID_COLOR = 'rgba(255,255,255,0.08)'

const baseChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      labels: { color: '#a0aec0', boxWidth: 12, font: { size: 11 } },
    },
    title: { display: false },
    tooltip: {
      backgroundColor: '#2d3748',
      titleColor: '#e2e8f0',
      bodyColor: '#a0aec0',
    },
  },
  scales: {
    x: {
      ticks: { color: '#718096', font: { size: 10 } },
      grid: { color: GRID_COLOR },
    },
    y: {
      ticks: { color: '#718096', font: { size: 10 } },
      grid: { color: GRID_COLOR },
    },
  },
}

export default function ObservabilityTab() {
  const [stats, setStats] = useState({
    txPerMin: rand(280, 380),
    latHigh: rand(35, 65),
    latLow: randFloat(1.4, 2.8),
    errorRate: randFloat(0.1, 0.5, 2),
  })

  const [latencyData, setLatencyData] = useState(makeLatencyData)
  const [queueData, setQueueData]     = useState(makeQueueData)

  useEffect(() => {
    const id = setInterval(() => {
      setStats({
        txPerMin: rand(280, 380),
        latHigh: rand(35, 65),
        latLow: randFloat(1.4, 2.8),
        errorRate: randFloat(0.1, 0.5, 2),
      })

      setLatencyData(prev => {
        const labels = [...prev.labels.slice(1), `${parseInt(prev.labels[prev.labels.length - 1]) + 5}s`]
        return {
          labels,
          datasets: [
            {
              ...prev.datasets[0],
              data: [...prev.datasets[0].data.slice(1), rand(40, 80)],
            },
            {
              ...prev.datasets[1],
              data: [...prev.datasets[1].data.slice(1), rand(1800, 2500)],
            },
          ],
        }
      })

      setQueueData(prev => {
        const labels = [...prev.labels.slice(1), `${parseInt(prev.labels[prev.labels.length - 1]) + 5}s`]
        return {
          labels,
          datasets: [
            {
              ...prev.datasets[0],
              data: [...prev.datasets[0].data.slice(1), rand(0, 40)],
            },
            {
              ...prev.datasets[1],
              data: [...prev.datasets[1].data.slice(1), rand(0, 20)],
            },
          ],
        }
      })
    }, 5000)
    return () => clearInterval(id)
  }, [])

  return (
    <div className="space-y-6">
      {/* Stats row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Transactions/min" value={stats.txPerMin} color="#e2e8f0" />
        <StatCard label="Avg latency (high)" value={`${stats.latHigh}ms`} color="#22c55e" />
        <StatCard label="Avg latency (low)" value={`${stats.latLow}s`} color="#e2e8f0" />
        <StatCard label="Error rate" value={`${stats.errorRate}%`} color="#22c55e" />
      </div>

      {/* Line chart */}
      <ChartCard title="Processing latency by priority (simulated)">
        <div style={{ height: 260 }}>
          <Line
            data={latencyData}
            options={{
              ...baseChartOptions,
              plugins: {
                ...baseChartOptions.plugins,
                title: { display: false },
              },
            }}
          />
        </div>
      </ChartCard>

      {/* Bar chart */}
      <ChartCard title="Queue depth over time (simulated)">
        <div style={{ height: 240 }}>
          <Bar
            data={queueData}
            options={{
              ...baseChartOptions,
              plugins: {
                ...baseChartOptions.plugins,
                title: { display: false },
              },
            }}
          />
        </div>
      </ChartCard>

      {/* Doughnut chart */}
      <ChartCard title="Transaction volume by type">
        <div className="flex justify-center" style={{ height: 260 }}>
          <Doughnut
            data={doughnutData}
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
                    label: ctx => ` ${ctx.label}: ${ctx.parsed}%`,
                  },
                },
              },
            }}
          />
        </div>
      </ChartCard>
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div
      className="rounded-lg p-4"
      style={{ backgroundColor: DARK_BG, border: '1px solid #2d3748' }}
    >
      <p className="text-xs mb-1" style={{ color: '#718096' }}>{label}</p>
      <p className="text-2xl font-bold" style={{ color }}>{value}</p>
    </div>
  )
}

function ChartCard({ title, children }) {
  return (
    <div
      className="rounded-lg p-5"
      style={{ backgroundColor: DARK_BG, border: '1px solid #2d3748' }}
    >
      <h2 className="text-sm font-semibold mb-4" style={{ color: '#a0aec0' }}>{title}</h2>
      {children}
    </div>
  )
}
