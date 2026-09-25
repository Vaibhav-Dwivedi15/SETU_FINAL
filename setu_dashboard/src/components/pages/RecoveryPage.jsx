import React, { useState } from 'react';
import { 
  LuPackage, LuUsers, LuCircleCheck, 
  LuSearch, LuMapPin, LuArrowRight, LuActivity, LuCheck
} from 'react-icons/lu';
import { EmptyState } from '../ui/Primitives';
import { MiscIcons } from '../../icons';

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
    <div style={{ padding: '20px', color: 'var(--text-primary)', background: 'var(--bg-primary)', minHeight: '100%' }}>
      {/* Metric Cards Banner */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '14px', marginBottom: '20px' }}>
        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--accent)', fontSize: '13px', fontWeight: 600 }}>
            <LuPackage /> Total Damage Reports
          </div>
          <div style={{ fontSize: '26px', fontWeight: 700, marginTop: '8px', color: 'var(--text-primary)' }}>{damageReports.length}</div>
          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Verified field submissions</span>
        </div>

        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--warning)', fontSize: '13px', fontWeight: 600 }}>
            <LuUsers /> Missing Persons
          </div>
          <div style={{ fontSize: '26px', fontWeight: 700, marginTop: '8px', color: 'var(--text-primary)' }}>{missingPersons.length}</div>
          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{missingPersons.filter(m => m.status === 'Reunited').length} Reunited / Safe</span>
        </div>

        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--success)', fontSize: '13px', fontWeight: 600 }}>
            <LuActivity /> Mesh ACK Delivery Rate
          </div>
          <div style={{ fontSize: '26px', fontWeight: 700, marginTop: '8px', color: 'var(--success)' }}>100%</div>
          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Sent → Relayed → Delivered</span>
        </div>
      </div>

      {/* Tab Switcher & Search Bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '14px', marginBottom: '18px' }}>
        <div style={{ display: 'flex', gap: '4px', background: 'var(--bg-surface-alt)', padding: '3px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-subtle)' }}>
          <button 
            onClick={() => setActiveTab('damage')} 
            style={{ 
              padding: '6px 14px', borderRadius: 'var(--radius-sm)', border: 'none', cursor: 'pointer', fontSize: '12px', fontWeight: 600,
              background: activeTab === 'damage' ? 'var(--accent)' : 'transparent', color: activeTab === 'damage' ? '#fff' : 'var(--text-secondary)'
            }}
          >
            Damage & Infrastructure ({damageReports.length})
          </button>
          <button 
            onClick={() => setActiveTab('missing')} 
            style={{ 
              padding: '6px 14px', borderRadius: 'var(--radius-sm)', border: 'none', cursor: 'pointer', fontSize: '12px', fontWeight: 600,
              background: activeTab === 'missing' ? 'var(--accent)' : 'transparent', color: activeTab === 'missing' ? '#fff' : 'var(--text-secondary)'
            }}
          >
            Missing Persons Registry ({missingPersons.length})
          </button>
        </div>

        <div style={{ position: 'relative', minWidth: '280px' }}>
          <LuSearch style={{ position: 'absolute', left: '12px', top: '11px', color: 'var(--text-muted)' }} />
          <input 
            type="text" 
            placeholder={activeTab === 'damage' ? 'Search damage report, location...' : 'Search missing person by name...'}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{ 
              width: '100%', background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', 
              padding: '8px 12px 8px 34px', color: 'var(--text-primary)', fontSize: '13px', outline: 'none' 
            }}
          />
        </div>
      </div>

      {/* Content Area */}
      {activeTab === 'damage' ? (
        filteredDamage.length === 0 ? (
          <EmptyState
            icon={MiscIcons.empty}
            title="NO DAMAGE REPORTS FOUND"
            description="No damage reports match your active search criteria."
          />
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: '16px' }}>
            {filteredDamage.map(report => (
              <div key={report.id} style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                  <span style={{ fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '4px', background: 'var(--bg-surface-alt)', color: 'var(--text-secondary)', border: '1px solid var(--border-subtle)' }}>
                    {report.category}
                  </span>
                  <span style={{ 
                    fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '4px',
                    background: report.severity === 'Critical' ? 'var(--danger-dim, rgba(239, 68, 68, 0.2))' : report.severity === 'High' ? 'var(--warning-dim, rgba(245, 158, 11, 0.2))' : 'var(--caution-dim, rgba(234, 179, 8, 0.2))',
                    color: report.severity === 'Critical' ? 'var(--danger)' : report.severity === 'High' ? 'var(--warning)' : 'var(--caution)'
                  }}>
                    {report.severity}
                  </span>
                </div>

                <h3 style={{ fontSize: '15px', fontWeight: 700, marginBottom: '6px', color: 'var(--text-primary)' }}>{report.title}</h3>
                <p style={{ fontSize: '13px', color: 'var(--text-secondary)', lineHeight: '1.5', marginBottom: '12px' }}>{report.description}</p>

                <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: 'var(--warning)', marginBottom: '14px' }}>
                  <LuMapPin /> {report.location}
                </div>

                {/* Delivery State Lifecycle: Sent -> Relayed -> Delivered */}
                <div style={{ background: 'var(--bg-surface-alt)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', marginBottom: '12px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '6px' }}>
                    <span>Packet Trajectory ({report.hopCount} hops)</span>
                    <span style={{ fontWeight: 700, color: report.status === 'Delivered' ? 'var(--success)' : 'var(--accent)' }}>
                      Status: {report.status}
                    </span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '11px', fontWeight: 600 }}>
                    <span style={{ color: 'var(--success)' }}>Sent</span>
                    <LuArrowRight style={{ color: 'var(--text-muted)' }} />
                    <span style={{ color: report.status === 'Relayed' || report.status === 'Delivered' ? 'var(--success)' : 'var(--text-muted)' }}>Relayed</span>
                    <LuArrowRight style={{ color: 'var(--text-muted)' }} />
                    <span style={{ color: report.status === 'Delivered' ? 'var(--success)' : 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '3px' }}>
                      {report.status === 'Delivered' && <LuCircleCheck />} Delivered (ACK)
                    </span>
                  </div>
                </div>

                {report.status !== 'Delivered' && (
                  <button 
                    onClick={() => advanceDamageStatus(report.id)}
                    style={{ 
                      width: '100%', padding: '8px', background: 'var(--accent)', color: '#fff', border: 'none', 
                      borderRadius: 'var(--radius-sm)', fontSize: '12px', fontWeight: 600, cursor: 'pointer' 
                    }}
                  >
                    Transmit Mesh ACK: Advance to {report.status === 'Sent' ? 'Relayed' : 'Delivered'}
                  </button>
                )}
              </div>
            ))}
          </div>
        )
      ) : (
        filteredMissing.length === 0 ? (
          <EmptyState
            icon={MiscIcons.empty}
            title="NO MISSING PERSONS FOUND"
            description="No registered missing persons match your active search query."
          />
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: '16px' }}>
            {filteredMissing.map(person => (
              <div key={person.id} style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                  <span style={{ fontSize: '16px', fontWeight: 700, color: 'var(--text-primary)' }}>{person.name}</span>
                  <span style={{ 
                    fontSize: '11px', fontWeight: 700, padding: '3px 8px', borderRadius: '4px',
                    background: person.status === 'Reunited' ? 'var(--success-dim, rgba(16, 185, 129, 0.2))' : person.status === 'Sighted' ? 'var(--warning-dim, rgba(245, 158, 11, 0.2))' : 'var(--danger-dim, rgba(239, 68, 68, 0.2))',
                    color: person.status === 'Reunited' ? 'var(--success)' : person.status === 'Sighted' ? 'var(--warning)' : 'var(--danger)'
                  }}>
                    {person.status}
                  </span>
                </div>

                <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px' }}>
                  Age: <strong style={{ color: 'var(--text-primary)' }}>{person.age}</strong> | Gender: <strong style={{ color: 'var(--text-primary)' }}>{person.gender}</strong>
                </div>

                <p style={{ fontSize: '13px', color: 'var(--text-secondary)', marginBottom: '12px', lineHeight: '1.5' }}>
                  <strong style={{ color: 'var(--warning)' }}>Last Seen:</strong> {person.lastSeen}
                </p>

                <div style={{ fontSize: '12px', color: 'var(--text-muted)', borderTop: '1px solid var(--border-subtle)', paddingTop: '10px', marginBottom: '12px' }}>
                  Reported by: <span style={{ color: 'var(--text-primary)' }}>{person.reportedBy}</span> ({person.contact})
                </div>

                {person.status !== 'Reunited' && (
                  <button 
                    onClick={() => markReunited(person.id)}
                    style={{ 
                      width: '100%', padding: '8px', background: 'var(--success)', color: '#fff', border: 'none', 
                      borderRadius: 'var(--radius-sm)', fontSize: '12px', fontWeight: 600, cursor: 'pointer', display: 'flex',
                      alignItems: 'center', justifyContent: 'center', gap: '6px'
                    }}
                  >
                    <LuCheck /> Confirm Sighting / Mark Reunited
                  </button>
                )}
              </div>
            ))}
          </div>
        )
      )}
    </div>
  );
}
