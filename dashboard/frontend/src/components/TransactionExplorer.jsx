import { useState, useMemo } from 'react'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const randInt   = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min
const randFloat = (min, max, dec = 1) => parseFloat((Math.random() * (max - min) + min).toFixed(dec))

const ALPHANUM = 'abcdefghijklmnopqrstuvwxyz0123456789'
const randomId = (len = 8) =>
  Array.from({ length: len }, () => ALPHANUM[Math.floor(Math.random() * ALPHANUM.length)]).join('')

const TYPES = ['purchase', 'withdrawal', 'transfer', 'deposit']

function generateTransactions(count) {
  return Array.from({ length: count }, () => {
    const amount = randInt(500, 99000)
    const priority =
      amount > 50000 ? 'critical' :
      amount > 10000 ? 'high'     :
      amount > 2000  ? 'medium'   : 'low'

    const roll = Math.random()
    const status =
      roll < 0.70 ? 'Clean'       :
      roll < 0.90 ? 'Risk breach' : 'Fraud alert'

    const isHighPriority = priority === 'high' || priority === 'critical'
    const latency = isHighPriority
      ? `${randInt(25, 75)}ms`
      : `${randFloat(1.0, 3.5)}s`

    return {
      id:       'txn-' + randomId(8),
      user_id:  'U-' + randInt(1001, 1010),
      type:     TYPES[Math.floor(Math.random() * TYPES.length)],
      amount:   '$' + amount.toLocaleString(),
      priority,
      status,
      latency,
    }
  })
}

// ---------------------------------------------------------------------------
// Badge styles
// ---------------------------------------------------------------------------
const PRIORITY_STYLES = {
  low:      { backgroundColor: '#374151', color: '#9ca3af' },
  medium:   { backgroundColor: '#1e3a5f', color: '#60a5fa' },
  high:     { backgroundColor: '#431407', color: '#fb923c' },
  critical: { backgroundColor: '#450a0a', color: '#f87171' },
}

const STATUS_STYLES = {
  'Clean':       { backgroundColor: '#14532d', color: '#86efac' },
  'Risk breach': { backgroundColor: '#431407', color: '#fdba74' },
  'Fraud alert': { backgroundColor: '#450a0a', color: '#f87171' },
}

function Badge({ label, styleMap }) {
  const s = styleMap[label] || { backgroundColor: '#374151', color: '#9ca3af' }
  return (
    <span
      className="px-2 py-0.5 rounded-full text-xs font-medium"
      style={s}
    >
      {label}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export default function TransactionExplorer() {
  const transactions = useMemo(() => generateTransactions(30), [])

  const [filterPriority, setFilterPriority] = useState('all')
  const [filterType,     setFilterType]     = useState('all')

  const filtered = transactions.filter(tx => {
    if (filterPriority !== 'all' && tx.priority !== filterPriority) return false
    if (filterType     !== 'all' && tx.type     !== filterType)     return false
    return true
  })

  const selectStyle = {
    backgroundColor: '#1a1d27',
    border: '1px solid #2d3748',
    borderRadius: 6,
    color: '#e2e8f0',
    padding: '6px 10px',
    fontSize: 13,
    outline: 'none',
    cursor: 'pointer',
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h2 className="text-sm font-semibold" style={{ color: '#a0aec0' }}>
          Transaction explorer — {filtered.length} transactions
        </h2>

        {/* Filters */}
        <div className="flex gap-3">
          <select
            value={filterPriority}
            onChange={e => setFilterPriority(e.target.value)}
            style={selectStyle}
          >
            <option value="all">All priorities</option>
            <option value="low">low</option>
            <option value="medium">medium</option>
            <option value="high">high</option>
            <option value="critical">critical</option>
          </select>

          <select
            value={filterType}
            onChange={e => setFilterType(e.target.value)}
            style={selectStyle}
          >
            <option value="all">All types</option>
            <option value="purchase">purchase</option>
            <option value="withdrawal">withdrawal</option>
            <option value="transfer">transfer</option>
            <option value="deposit">deposit</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div
        className="rounded-lg overflow-hidden"
        style={{ border: '1px solid #2d3748' }}
      >
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr style={{ backgroundColor: '#161b27', borderBottom: '1px solid #2d3748' }}>
                {['Transaction ID', 'User ID', 'Type', 'Amount', 'Priority', 'Status', 'Latency'].map(col => (
                  <th
                    key={col}
                    className="px-4 py-3 text-left font-medium"
                    style={{ color: '#718096' }}
                  >
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td
                    colSpan={7}
                    className="px-4 py-6 text-center"
                    style={{ color: '#4a5568', backgroundColor: '#1a1d27' }}
                  >
                    No transactions match the selected filters.
                  </td>
                </tr>
              ) : (
                filtered.map((tx, i) => (
                  <tr
                    key={tx.id}
                    style={{
                      backgroundColor: i % 2 === 0 ? '#1a1d27' : '#1e2230',
                      borderBottom: '1px solid #2d3748',
                    }}
                  >
                    <td className="px-4 py-2.5 font-mono" style={{ color: '#60a5fa' }}>
                      {tx.id}
                    </td>
                    <td className="px-4 py-2.5" style={{ color: '#e2e8f0' }}>
                      {tx.user_id}
                    </td>
                    <td className="px-4 py-2.5 capitalize" style={{ color: '#e2e8f0' }}>
                      {tx.type}
                    </td>
                    <td className="px-4 py-2.5 font-medium" style={{ color: '#e2e8f0' }}>
                      {tx.amount}
                    </td>
                    <td className="px-4 py-2.5">
                      <Badge label={tx.priority} styleMap={PRIORITY_STYLES} />
                    </td>
                    <td className="px-4 py-2.5">
                      <Badge label={tx.status} styleMap={STATUS_STYLES} />
                    </td>
                    <td className="px-4 py-2.5 font-mono" style={{ color: '#a0aec0' }}>
                      {tx.latency}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
