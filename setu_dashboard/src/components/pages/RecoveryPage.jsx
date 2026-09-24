import React, { useState } from 'react';
import { 
  LuPackage, LuUsers, LuCircleCheck, 
  LuSearch, LuMapPin, LuArrowRight, LuActivity, LuCheck
} from 'react-icons/lu';

const INITIAL_DAMAGE = [
  {
    id: 'DMG-101',
    category: 'ROAD_BLOCK',
    title: 'Culvert Breached & Flooded',
    description: 'Culvert breached near Old Naini Bund Road. Water overflowing 2 feet across arterial road. Heavy vehicles stranded.',
    location: 'Old Naini Bund Road, Prayagraj',
    severity: 'High',
    reportedAt: '25 mins ago',
    status: 'Relayed', // Sent -> Relayed -> Delivered (ACK lifecycle)
    hopCount: 3
  },
  {
    id: 'DMG-102',
    category: 'POWER_OUTAGE',
    title: 'Substation Feeder Submerged',
    description: '3 high-tension poles submerged and sparking near Katra feeder. Emergency grid trip requested.',
    location: 'Katra Substation Sector 4, Prayagraj',
    severity: 'Critical',
    reportedAt: '40 mins ago',
    status: 'Delivered',
    hopCount: 1
  },
  {
    id: 'DMG-103',
    category: 'STRUCTURAL',
    title: 'Basement Wall Crack',
    description: 'Basement structural crack observed in commercial complex after floodwater receded.',
    location: 'Civil Lines Crossing, Prayagraj',
    severity: 'Medium',
    reportedAt: '1 hour ago',
    status: 'Sent',
    hopCount: 2
  }
];

const INITIAL_MISSING = [
  {
    id: 'MIS-201',
    name: 'Aarav Sharma',
    age: 12,
    gender: 'Male',
    lastSeen: 'Near Daraganj Relief Point during sudden evacuation',
    reportedBy: 'Sunita Sharma (Mother)',
    status: 'Searching',
    contact: '+91 98765 43210'
  },
  {
    id: 'MIS-202',
    name: 'Rameshwar Nath',
    age: 71,
    gender: 'Male',
    lastSeen: 'George Town Medical Camp',
    reportedBy: 'Kavita Nath (Daughter)',
    status: 'Sighted',
    contact: '+91 98765 43211'
  },
  {
    id: 'MIS-203',
    name: 'Priya Patel',
    age: 24,
    gender: 'Female',
    lastSeen: 'Naini Railway Station Approach',
    reportedBy: 'Deepak Patel (Brother)',
    status: 'Reunited',
    contact: '+91 98765 43212'
  }
];

export default function RecoveryPage() {
  const [activeTab, setActiveTab] = useState('damage');
  const [damageReports, setDamageReports] = useState(INITIAL_DAMAGE);
  const [missingPersons, setMissingPersons] = useState(INITIAL_MISSING);
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('ALL');

  // Transition recovery status: Sent -> Relayed -> Delivered (ACK listener)
  const advanceDamageStatus = (id) => {
    setDamageReports(prev => prev.map(item => {
      if (item.id === id) {
        let nextStatus = 'Delivered';
        if (item.status === 'Sent') nextStatus = 'Relayed';
        else if (item.status === 'Relayed') nextStatus = 'Delivered';
        return { ...item, status: nextStatus };
      }
      return item;
    }));
  };

  const markReunited = (id) => {
    setMissingPersons(prev => prev.map(p => p.id === id ? { ...p, status: 'Reunited' } : p));
  };

  const filteredDamage = damageReports.filter(d => {
    const matchCat = categoryFilter === 'ALL' || d.category === categoryFilter;
    const matchSearch = d.title.toLowerCase().includes(searchQuery.toLowerCase()) || 
                        d.location.toLowerCase().includes(searchQuery.toLowerCase());
    return matchCat && matchSearch;
  });

  const filteredMissing = missingPersons.filter(m => 
    m.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
    m.lastSeen.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div style={{ padding: '24px', color: '#f1f5f9', background: 'var(--bg-primary, #0b1329)', minHeight: '100%' }}>
      {/* Metric Cards Banner */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px', marginBottom: '24px' }}>
        <div style={{ background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#38bdf8', fontSize: '13px', fontWeight: 600 }}>
            <LuPackage /> Total Damage Reports
          </div>
          <div style={{ fontSize: '28px', fontWeight: 800, marginTop: '8px' }}>{damageReports.length}</div>
          <span style={{ fontSize: '11px', color: '#94a3b8' }}>Verified field submissions</span>
        </div>

        <div style={{ background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#f59e0b', fontSize: '13px', fontWeight: 600 }}>
            <LuUsers /> Missing Persons
          </div>
          <div style={{ fontSize: '28px', fontWeight: 800, marginTop: '8px' }}>{missingPersons.length}</div>
          <span style={{ fontSize: '11px', color: '#94a3b8' }}>{missingPersons.filter(m => m.status === 'Reunited').length} Reunited / Safe</span>
        </div>

        <div style={{ background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#10b981', fontSize: '13px', fontWeight: 600 }}>
            <LuActivity /> Mesh ACK Delivery Rate
          </div>
          <div style={{ fontSize: '28px', fontWeight: 800, marginTop: '8px', color: '#10b981' }}>100%</div>
          <span style={{ fontSize: '11px', color: '#94a3b8' }}>Sent â†’ Relayed â†’ Delivered</span>
        </div>
      </div>

      {/* Tab Switcher & Search Bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px', marginBottom: '20px' }}>
        <div style={{ display: 'flex', gap: '8px', background: 'var(--bg-surface, #131f3d)', padding: '4px', borderRadius: '10px', border: '1px solid var(--border-color, #1e293b)' }}>
          <button 
            onClick={() => setActiveTab('damage')} 
            style={{ 
              padding: '8px 16px', borderRadius: '8px', border: 'none', cursor: 'pointer', fontSize: '13px', fontWeight: 600,
              background: activeTab === 'damage' ? '#ef4444' : 'transparent', color: activeTab === 'damage' ? '#fff' : '#94a3b8'
            }}
          >
            Damage & Infrastructure ({damageReports.length})
          </button>
          <button 
            onClick={() => setActiveTab('missing')} 
            style={{ 
              padding: '8px 16px', borderRadius: '8px', border: 'none', cursor: 'pointer', fontSize: '13px', fontWeight: 600,
              background: activeTab === 'missing' ? '#ef4444' : 'transparent', color: activeTab === 'missing' ? '#fff' : '#94a3b8'
            }}
          >
            Missing Persons Registry ({missingPersons.length})
          </button>
        </div>

        <div style={{ position: 'relative', minWidth: '280px' }}>
          <LuSearch style={{ position: 'absolute', left: '12px', top: '12px', color: '#64748b' }} />
          <input 
            type="text" 
            placeholder={activeTab === 'damage' ? 'Search damage report, location...' : 'Search missing person by name...'}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{ 
              width: '100%', background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '8px', 
              padding: '9px 12px 9px 36px', color: '#fff', fontSize: '13px', outline: 'none' 
            }}
          />
        </div>
      </div>

      {/* Content Area */}
      {activeTab === 'damage' ? (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: '16px' }}>
          {filteredDamage.map(report => (
            <div key={report.id} style={{ background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '12px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <span style={{ fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '6px', background: '#334155', color: '#cbd5e1' }}>
                  {report.category}
                </span>
                <span style={{ 
                  fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '6px',
                  background: report.severity === 'Critical' ? '#991b1b' : report.severity === 'High' ? '#c2410c' : '#854d0e',
                  color: '#fff'
                }}>
                  {report.severity}
                </span>
              </div>

              <h3 style={{ fontSize: '15px', fontWeight: 700, marginBottom: '6px', color: '#f8fafc' }}>{report.title}</h3>
              <p style={{ fontSize: '13px', color: '#cbd5e1', lineHeight: '1.5', marginBottom: '12px' }}>{report.description}</p>

              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: '#fbbf24', marginBottom: '16px' }}>
                <LuMapPin /> {report.location}
              </div>

              {/* Delivery State Lifecycle: Sent -> Relayed -> Delivered */}
              <div style={{ background: 'var(--bg-primary, #0b1329)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '8px', padding: '10px 14px', marginBottom: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '11px', color: '#94a3b8', marginBottom: '6px' }}>
                  <span>Packet Trajectory ({report.hopCount} hops)</span>
                  <span style={{ fontWeight: 700, color: report.status === 'Delivered' ? '#10b981' : '#38bdf8' }}>
                    Status: {report.status}
                  </span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '11px', fontWeight: 600 }}>
                  <span style={{ color: '#10b981' }}>Sent</span>
                  <LuArrowRight style={{ color: '#475569' }} />
                  <span style={{ color: report.status === 'Relayed' || report.status === 'Delivered' ? '#10b981' : '#64748b' }}>Relayed</span>
                  <LuArrowRight style={{ color: '#475569' }} />
                  <span style={{ color: report.status === 'Delivered' ? '#10b981' : '#64748b', display: 'flex', alignItems: 'center', gap: '3px' }}>
                    {report.status === 'Delivered' && <LuCircleCheck />} Delivered (ACK)
                  </span>
                </div>
              </div>

              {report.status !== 'Delivered' && (
                <button 
                  onClick={() => advanceDamageStatus(report.id)}
                  style={{ 
                    width: '100%', padding: '8px', background: '#2563eb', color: '#fff', border: 'none', 
                    borderRadius: '6px', fontSize: '12px', fontWeight: 600, cursor: 'pointer' 
                  }}
                >
                  Simulate ACK: Advance to {report.status === 'Sent' ? 'Relayed' : 'Delivered'}
                </button>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: '16px' }}>
          {filteredMissing.map(person => (
            <div key={person.id} style={{ background: 'var(--bg-surface, #131f3d)', border: '1px solid var(--border-color, #1e293b)', borderRadius: '12px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <span style={{ fontSize: '16px', fontWeight: 700, color: '#f8fafc' }}>{person.name}</span>
                <span style={{ 
                  fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '6px',
                  background: person.status === 'Reunited' ? '#065f46' : person.status === 'Sighted' ? '#92400e' : '#991b1b',
                  color: '#fff'
                }}>
                  {person.status}
                </span>
              </div>

              <div style={{ fontSize: '12px', color: '#94a3b8', marginBottom: '8px' }}>
                Age: <strong style={{ color: '#f1f5f9' }}>{person.age}</strong> | Gender: <strong style={{ color: '#f1f5f9' }}>{person.gender}</strong>
              </div>

              <p style={{ fontSize: '13px', color: '#cbd5e1', marginBottom: '12px', lineHeight: '1.5' }}>
                <strong style={{ color: '#fbbf24' }}>Last Seen:</strong> {person.lastSeen}
              </p>

              <div style={{ fontSize: '12px', color: '#94a3b8', borderTop: '1px solid var(--border-color, #1e293b)', paddingTop: '10px', marginBottom: '12px' }}>
                Reported by: <span style={{ color: '#f1f5f9' }}>{person.reportedBy}</span> ({person.contact})
              </div>

              {person.status !== 'Reunited' && (
                <button 
                  onClick={() => markReunited(person.id)}
                  style={{ 
                    width: '100%', padding: '8px', background: '#059669', color: '#fff', border: 'none', 
                    borderRadius: '6px', fontSize: '12px', fontWeight: 600, cursor: 'pointer', display: 'flex',
                    alignItems: 'center', justifyContent: 'center', gap: '6px'
                  }}
                >
                  <LuCheck /> Confirm Sighting / Mark Reunited
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
