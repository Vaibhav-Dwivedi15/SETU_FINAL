import React, { useState } from 'react';
import { 
  LuPackage, LuUsers, LuCircleCheck, 
  LuSearch, LuMapPin, LuArrowRight, LuActivity, LuCheck
} from 'react-icons/lu';
import { EmptyState, PriorityBadge } from '../ui/Primitives';
import { MiscIcons, ActionIcons } from '../../icons';
import './recovery-v2.css';

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

  const categories = ['ALL', ...new Set(damageReports.map(d => d.category))];
  const reunitedCount = missingPersons.filter(m => m.status === 'Reunited').length;

  return (
    <div className="recovery-page">
      {/* Top Operational Intelligence Banner */}
      <div className="recovery-hero-banner">
        <div className="recovery-hero-left">
          <h2>Disaster Recovery &amp; Reunification Operations</h2>
          <p>Verified field assessments, structural damage reports, and missing persons registry.</p>
        </div>
      </div>

      {/* Metrics Row */}
      <div className="recovery-stats-strip">
        <div className="recovery-stat-tile">
          <div className="recovery-stat-icon damage">
            <LuPackage />
          </div>
          <div className="recovery-stat-meta">
            <span>DAMAGE ASSESSMENTS</span>
            <strong>{damageReports.length}</strong>
            <small>Verified field submissions</small>
          </div>
        </div>

        <div className="recovery-stat-tile">
          <div className="recovery-stat-icon missing">
            <LuUsers />
          </div>
          <div className="recovery-stat-meta">
            <span>MISSING PERSONS</span>
            <strong>{missingPersons.length}</strong>
            <small>{reunitedCount} Reunited / Verified Safe</small>
          </div>
        </div>

        <div className="recovery-stat-tile">
          <div className="recovery-stat-icon ack">
            <LuActivity />
          </div>
          <div className="recovery-stat-meta">
            <span>MESH ACK DELIVERY RATE</span>
            <strong>100%</strong>
            <small>Sent → Relayed → Delivered (ACK)</small>
          </div>
        </div>
      </div>

      {/* Navigation & Search Bar */}
      <div className="recovery-nav-bar">
        <div className="recovery-tabs" role="tablist">
          <button 
            role="tab"
            aria-selected={activeTab === 'damage'}
            className={`recovery-tab-btn ${activeTab === 'damage' ? 'active' : ''}`}
            onClick={() => setActiveTab('damage')}
          >
            <LuPackage /> Damage &amp; Infrastructure ({damageReports.length})
          </button>
          <button 
            role="tab"
            aria-selected={activeTab === 'missing'}
            className={`recovery-tab-btn ${activeTab === 'missing' ? 'active' : ''}`}
            onClick={() => setActiveTab('missing')}
          >
            <LuUsers /> Missing Persons Registry ({missingPersons.length})
          </button>
        </div>

        <div className="recovery-search-filter">
          <div className="recovery-search-box">
            <LuSearch />
            <input 
              type="text" 
              className="recovery-search-input"
              placeholder={activeTab === 'damage' ? 'Search damage, location...' : 'Search missing person...'}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              aria-label="Search records"
            />
          </div>

          {activeTab === 'damage' && (
            <select
              className="recovery-filter-select"
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
              aria-label="Filter category"
            >
              {categories.map(c => (
                <option key={c} value={c}>{c === 'ALL' ? 'All Categories' : c}</option>
              ))}
            </select>
          )}
        </div>
      </div>

      {/* Content Stream */}
      {activeTab === 'damage' ? (
        filteredDamage.length === 0 ? (
          <EmptyState
            icon={MiscIcons.empty}
            title="NO DAMAGE REPORTS MATCH CRITERIA"
            description="No damage reports match your active search and category filter. Try clearing filters to view all assessments."
          />
        ) : (
          <div className="recovery-grid">
            {filteredDamage.map(report => (
              <div key={report.id} className="recovery-card">
                <div className="recovery-card-top">
                  <span className="recovery-tag">{report.category}</span>
                  <PriorityBadge priority={report.severity} size="sm" />
                </div>

                <h3 className="recovery-card-title">{report.title}</h3>
                <p className="recovery-card-desc">{report.description}</p>

                <div className="recovery-location">
                  <LuMapPin />
                  <span>{report.location}</span>
                </div>

                <div className="recovery-trajectory">
                  <div className="recovery-trajectory-meta">
                    <span className="ds-mono">Mesh Trajectory ({report.hopCount} hops)</span>
                    <strong className="ds-mono" style={{ color: report.status === 'Delivered' ? 'var(--success)' : 'var(--accent)' }}>
                      {report.status}
                    </strong>
                  </div>
                  <div className="recovery-trajectory-steps">
                    <span className="recovery-step done">Sent</span>
                    <LuArrowRight style={{ color: 'var(--text-dim)' }} />
                    <span className={`recovery-step ${report.status === 'Relayed' || report.status === 'Delivered' ? 'done' : ''}`}>
                      Relayed
                    </span>
                    <LuArrowRight style={{ color: 'var(--text-dim)' }} />
                    <span className={`recovery-step ${report.status === 'Delivered' ? 'done' : ''}`}>
                      {report.status === 'Delivered' && <LuCircleCheck />} Delivered (ACK)
                    </span>
                  </div>
                </div>

                {report.status !== 'Delivered' && (
                  <button 
                    className="recovery-action-btn"
                    onClick={() => advanceDamageStatus(report.id)}
                  >
                    <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
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
          <div className="recovery-grid">
            {filteredMissing.map(person => {
              const isReunited = person.status === 'Reunited';
              const isSighted = person.status === 'Sighted';
              return (
                <div key={person.id} className="recovery-card">
                  <div className="recovery-card-top">
                    <h3 className="recovery-card-title">{person.name}</h3>
                    <span 
                      className="recovery-tag"
                      style={{
                        background: isReunited ? 'var(--success-dim)' : isSighted ? 'var(--warning-dim)' : 'var(--danger-dim)',
                        color: isReunited ? 'var(--success)' : isSighted ? 'var(--warning)' : 'var(--danger)',
                        borderColor: isReunited ? 'var(--success-border)' : isSighted ? 'var(--warning-border)' : 'var(--danger-border)',
                      }}
                    >
                      {person.status}
                    </span>
                  </div>

                  <div className="missing-person-details">
                    <span>Age: <strong>{person.age}</strong></span>
                    <span>•</span>
                    <span>Gender: <strong>{person.gender}</strong></span>
                  </div>

                  <p className="recovery-card-desc">
                    <strong style={{ color: 'var(--warning)' }}>Last Seen:</strong> {person.lastSeen}
                  </p>

                  <div className="missing-reporter">
                    Reported by: <span>{person.reportedBy}</span> ({person.contact})
                  </div>

                  {!isReunited && (
                    <button 
                      className="recovery-action-btn reunited"
                      onClick={() => markReunited(person.id)}
                    >
                      <LuCheck /> Confirm Sighting / Mark Reunited
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )
      )}
    </div>
  );
}
