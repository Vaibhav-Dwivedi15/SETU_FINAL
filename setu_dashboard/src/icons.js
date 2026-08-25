// =====================================================
// SETU Dashboard — Icon Registry
// =====================================================
//
// Single source of truth for every icon in the product. No component
// should import from react-icons directly or use an emoji character as
// UI iconography — import from here instead, so the whole product
// shares one consistent visual family (Lucide, via react-icons/lu,
// already an installed dependency — no new package added).
//
// Organized by purpose, not alphabetically, so it's easy to find "what
// icon represents X" rather than "what icon is named Y".

import {
  // Navigation / operations
  LuLayoutDashboard, LuMap, LuRadio, LuActivity, LuChartColumn,
  LuLayoutGrid, LuNetwork, LuTruck, LuUsers, LuPackage,
  LuSettings, LuHistory,
  // Emergency categories
  LuShieldAlert, LuBaby, LuHeartHandshake, LuSiren, LuAmbulance,
  LuCar, LuFlame, LuWaves, LuTriangleAlert,
  // Status / severity
  LuCircleCheck, LuCircleHelp, LuCircleDot, LuClock, LuCircleX,
  // Delivery pipeline
  LuSatelliteDish, LuServer, LuMessageSquare, LuLandmark, LuUsersRound,
  LuCircleCheckBig,
  // Actions
  LuEye, LuNavigation, LuPhone, LuX, LuCheck, LuChevronDown,
  LuChevronRight, LuSearch, LuBell, LuGlobe, LuSun, LuMoon,
  LuRefreshCw, LuMapPin, LuCopy, LuPlus,
  // Charts / stats / misc additions (Block 3)
  LuChartPie, LuDownload, LuVolume2, LuTrendingUp, LuTrendingDown, LuMinus,
  // Misc / empty states
  LuInbox, LuWifiOff, LuLink,
} from "react-icons/lu";

export const NavIcons = {
  overview: LuLayoutDashboard,
  liveMap: LuMap,
  liveIncidents: LuRadio,
  responseCenter: LuActivity,
  analytics: LuChartColumn,
  categories: LuLayoutGrid,
  networkHealth: LuNetwork,
  responseUnits: LuTruck,
  teams: LuUsers,
  resources: LuPackage,
  settings: LuSettings,
  activity: LuHistory,
};

export const CategoryIcons = {
  women_safety: LuShieldAlert,
  child_safety: LuBaby,
  senior_citizen: LuHeartHandshake,
  violence: LuTriangleAlert,
  medical: LuAmbulance,
  accident: LuCar,
  fire: LuFlame,
  natural_disaster: LuWaves,
  general_sos: LuSiren,
};

export const StatusIcons = {
  confirmed: LuCircleCheck,
  unknown: LuCircleHelp,
  pending: LuCircleDot,
  active: LuClock,
  closed: LuCircleCheckBig,
  failed: LuCircleX,
};

export const PipelineIcons = {
  meshRelay: LuSatelliteDish,
  backendReceipt: LuServer,
  sms: LuMessageSquare,
  government: LuLandmark,
  community: LuUsersRound,
  resolution: LuCircleCheckBig,
};

export const ActionIcons = {
  view: LuEye,
  respond: LuHeartHandshake,
  navigate: LuNavigation,
  call: LuPhone,
  dismiss: LuX,
  confirm: LuCheck,
  chevronDown: LuChevronDown,
  chevronRight: LuChevronRight,
  search: LuSearch,
  notifications: LuBell,
  language: LuGlobe,
  themeLight: LuSun,
  themeDark: LuMoon,
  refresh: LuRefreshCw,
  location: LuMapPin,
  copy: LuCopy,
  add: LuPlus,
  chartPie: LuChartPie,
  download: LuDownload,
  volume: LuVolume2,
  trendUp: LuTrendingUp,
  trendDown: LuTrendingDown,
  trendFlat: LuMinus,
};

export const MiscIcons = {
  empty: LuInbox,
  offline: LuWifiOff,
  merged: LuLink,
  alert: LuTriangleAlert,
};

/** Every category key that has no matching backend enum value yet
 *  (see incidentCategories.js's own honesty note) — used to render
 *  those categories with a visually receded treatment. */
export const AI_ONLY_CATEGORIES = new Set([
  "women_safety", "child_safety", "senior_citizen", "violence",
]);
