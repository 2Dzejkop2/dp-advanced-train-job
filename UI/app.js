
let questClaimQueue = [];
let questClaimInProgress = false;
async function processQuestClaimQueue() {
  if (questClaimInProgress || questClaimQueue.length === 0) return;
  questClaimInProgress = true;
  const { quest, questId, profileType } = questClaimQueue.shift();
  quest.claimPending = true;
  quest.claimed = true;
  queueRenderAll();
  const result = await nui('godtrain:claimQuest', { questId, profileType });
  if (result.ok && result.panel) {
    panelData = result.panel;
    queueRenderAll();
  } else {
    quest.claimPending = false;
    quest.claimed = false;
    queueRenderAll();
  }
  questClaimInProgress = false;
  if (questClaimQueue.length > 0) setTimeout(processQuestClaimQueue, 0);
}
const app = document.getElementById('app');
const hud = document.getElementById('hud');
const hudEditBar = document.getElementById('hudEditBar');
const hudEditClose = document.getElementById('hudEditClose');
const hudEditReset = document.getElementById('hudEditReset');
const hudScaleLabel = document.getElementById('hudScaleLabel');
const hudScaleRange = document.getElementById('hudScaleRange');
const hudDragHandle = document.getElementById('hudDragHandle');
const hudItems = Array.from(document.querySelectorAll('[data-hud-item]'));
const builtInTextUI = document.getElementById('builtInTextUI');
const builtInTextUIKey = document.getElementById('builtInTextUIKey');
const builtInTextUIText = document.getElementById('builtInTextUIText');

const playerName = document.getElementById('playerName');
const playerRank = document.getElementById('playerRank');
const playerXp = document.getElementById('playerXp');
const xpText = document.getElementById('xpText');
const rankBar = document.getElementById('rankBar');

const companyTitleMain = document.getElementById('companyTitleMain');
const companyTitleSub = document.getElementById('companyTitleSub');
const companyGlow = document.querySelector('.company-glow');
const companyDesc = document.getElementById('companyDesc');
const buyLicenseTitle = document.getElementById('buyLicenseTitle');
const buyLicenseHint = document.getElementById('buyLicenseHint');
const xpLabel = document.getElementById('xpLabel');

const licenseTabs = document.getElementById('licenseTabs');
const rankCards = Array.from(document.querySelectorAll('.rank-card'));
const rankButtons = Array.from(document.querySelectorAll('[data-rank-button]'));

const paymentModal = document.getElementById('paymentModal');
const paymentText = document.getElementById('paymentText');
const paymentModalHeader = document.getElementById('paymentModalHeader');
const payCash = document.getElementById('payCash');
const payBank = document.getElementById('payBank');

const questModal = document.getElementById('questModal');
const questList = document.getElementById('questList');
const questModalTitle = document.getElementById('questModalTitle');
const questModalSubtitle = document.getElementById('questModalSubtitle');

const questsBtn = document.getElementById('questsBtn');
const closeQuest = document.getElementById('closeQuest');
const hudCommandHint = document.getElementById('hudCommandHint');
const hudEditCommandHint = document.getElementById('hudEditCommandHint');

const hudTitle = document.getElementById('hudTitle');
const hudStatus = document.getElementById('hudStatus');
const hudNextStationLabel = document.getElementById('hudNextStationLabel');
const hudNextStation = document.getElementById('hudNextStation');
const hudDistanceLabel = document.getElementById('hudDistanceLabel');
const hudDistance = document.getElementById('hudDistance');
const hudKm = document.getElementById('hudKm');
const hudRouteKmLabel = document.getElementById('hudRouteKmLabel');
const hudTotal = document.getElementById('hudTotal');
const hudTotalLabel = document.getElementById('hudTotalLabel');
const hudStopsLabel = document.getElementById('hudStopsLabel');
const hudStops = document.getElementById('hudStops');
const hudXpLabel = document.getElementById('hudXpLabel');
const hudXp = document.getElementById('hudXp');
const hudSpeedLimitLabel = document.getElementById('hudSpeedLimitLabel');
const hudSpeedLimit = document.getElementById('hudSpeedLimit');
const hudCargoLabel = document.getElementById('hudCargoLabel');
const hudCargoCount = document.getElementById('hudCargoCount');
const hudLiveEarningsLabel = document.getElementById('hudLiveEarningsLabel');
const hudLiveEarnings = document.getElementById('hudLiveEarnings');
const hudPenaltyLabel = document.getElementById('hudPenaltyLabel');
const hudPenalty = document.getElementById('hudPenalty');
const hudCancelLabel = document.getElementById('hudCancelLabel');
const hudCancel = document.getElementById('hudCancel');
const hudCancelProgress = document.getElementById('hudCancelProgress');
const hudTimerBg = document.querySelector('.hud-timerbg');
const hudTimer = document.querySelector('.hud-timer');
const hudAssistant = document.querySelector('.hud-assistant');
const hudAssistantBody = document.querySelector('.hud-assistant__body');
const hudAssistantRow = document.querySelector('.hud-assistant__row');
const hudAssistantTitle = document.querySelector('.hud-assistant__title');
const hudAssistantSignal = document.querySelector('.hud-assistant__signal');
const hudAssistantLoading = document.querySelector('.hud-assistant__loading');
const hudAssistantDesc = document.querySelector('.hud-assistant__desc');
const hudAssistantSegments = Array.from(document.querySelectorAll('.hud-assistant__segment-fill'));
const avatarFront = document.querySelector('.avatar-front');
const avatarBack = document.querySelector('.avatar-back');

let panelData = null;
let selectedRouteId = null;
let selectedRankForPayment = null;
let renderQueued = false;
let avatarLoadNonce = 0;
let hudEditMode = false;
let lastStaticTextSignature = '';
let lastAvatarSignature = '';
let lastHudUpdateSignature = '';
let pendingHudModel = null;
let hudRenderQueued = false;
let hudLayout = { leftPct: 50.0, topPct: 1.35, scale: 0.92, hiddenItems: {} };
let hudDragState = null;
let hudBackgrounded = false;
const defaultHudLayout = { leftPct: 50.0, topPct: 1.35, scale: 0.92, hiddenItems: {} };
const hudEditorConfig = {
  scale: { minPct: 75, maxPct: 220, stepPct: 1 },
  labels: {}
};
const rankBarSegments = rankBar ? Array.from(rankBar.querySelectorAll('span')) : [];
const rankCardRefs = rankCards.map(card => ({
  card,
  titleEl: card.querySelector('.rank-card-title'),
  descEl: card.querySelector('.rank-card-desc'),
  avatarEl: card.querySelector('.rank-card-avatar'),
  metricEls: card.querySelectorAll('.rank-card-metric-value'),
  metricLabelEls: card.querySelectorAll('.rank-card-metric-label'),
  unlockLabelEl: card.querySelector('.rank-card-unlock-label'),
  unlockValueEl: card.querySelector('.rank-card-unlock-value'),
  unlockFillEl: card.querySelector('.rank-card-unlock-fill'),
  unlockWrapEl: card.querySelector('.rank-card-unlock'),
  stateEl: card.querySelector('.rank-card-state'),
  img: card.querySelector('.rank-card-img')
}));

function setText(el, value) {
  if (!el) return;
  const next = String(value ?? '');
  if (el.textContent !== next) el.textContent = next;
}

function setHtml(el, value) {
  if (!el) return;
  const next = String(value ?? '');
  if (el.innerHTML !== next) el.innerHTML = next;
}

function setStyle(el, prop, value) {
  if (!el) return;
  if (el.style[prop] !== value) el.style[prop] = value;
}

function getXpLevelStep() {
  return Math.max(1, Number(panelData?.ui?.xpLevelStep || 500));
}

function applyAvatarImage(src, fallback) {
  const resolvedFallback = fallback || 'assets/avatar.png';
  const nonce = ++avatarLoadNonce;
  let imageSrc = src || '';
  if (imageSrc && !/^https?:\/\//i.test(imageSrc) && !/^data:/i.test(imageSrc) && !/^nui:\/\//i.test(imageSrc) && !imageSrc.startsWith('assets/')) {
    imageSrc = `https://nui-img/${imageSrc}/${imageSrc}`;
  }
  const resolvedSrc = imageSrc ? `${imageSrc}${imageSrc.includes('?') ? '&' : '?'}v=${nonce}` : resolvedFallback;
  [avatarFront, avatarBack].forEach(img => {
    if (!img) return;
    img.onerror = () => {
      if (img.dataset.fallbackApplied === '1') return;
      img.dataset.fallbackApplied = '1';
      img.src = resolvedFallback;
    };
    img.onload = () => {
      img.dataset.fallbackApplied = '0';
    };
    img.src = resolvedSrc;
  });
}

function hardResetTransparency() {
  if (document.documentElement) {
    document.documentElement.style.setProperty('background', 'transparent', 'important');
    document.documentElement.style.setProperty('background-color', 'transparent', 'important');
  }

  if (document.body) {
    document.body.style.setProperty('background', 'transparent', 'important');
    document.body.style.setProperty('background-color', 'transparent', 'important');
  }

  if (app) {
    app.style.setProperty('background', 'transparent', 'important');
    app.style.setProperty('background-color', 'transparent', 'important');
  }
}

function setHudBackgrounded(enabled) {
  hudBackgrounded = !!enabled;
  if (!hud) return;
  hud.classList.toggle('hud--backgrounded', hudBackgrounded);
}

if (app) {
  app.classList.remove('active');
  app.style.display = 'none';
}
document.body?.classList?.remove('ui-panel-open');
hardResetTransparency();

const fallbackLocale = {
  companyTitleMain: 'RAIL',
  companyTitleSub: 'COMPANY',
  companyDescription: 'From rookie to veteran, a full rail operator career you can actually retire from.',
  buyLicenseTitle: 'BUY LICENSE',
  buyLicenseHint: 'You need to get a license for every level you qualify for. If you do not get the proper license, there is a chance you might get fined.',
  buttonQuests: 'QUESTS',
  xpLabel: 'XP',
  levelShort: 'LVL',
  playerLevelMeta: '%s XP TO LVL %s',
  rankUnlockProgress: 'UNLOCK PROGRESS',
  rankStateActive: 'ACTIVE',
  rankStateNext: 'NEXT',
  rankStateLocked: 'LOCKED',
  modalPaymentText: 'This license is a one-time purchase. Will be registered under your name. How would you like to make the %s payment?',
  payCash: 'CASH',
  payBank: 'BANK',
  questTitle: 'QUEST LIST',
  questSubtitle: 'Complete tasks to claim rewards.',
  noQuests: 'No quests available.',
  questClaimReady: 'Click to claim',
  questPeriodDaily: 'DAILY',
  questPeriodWeekly: 'WEEKLY',
  rankStationEarning: 'STATION EARNING',
  rankRouteBonus: 'ROUTE BONUS',
  rankButtonStart: 'Start %s',
  rankButtonActive: 'Start %s (Active)',
  rankButtonLocked: 'LOCKED',
  rankButtonBuy: 'BUY',
  hudTitle: 'Train Job Status',
  hudNextStation: 'Next Station',
  hudDistance: 'Distance',
  hudKm: 'KM',
  hudTotal: 'Total mileage',
  hudStops: 'Stops',
  hudSpeedLimit: 'Speed Limit',
  hudNoLimit: 'NO LIMIT',
  hudXp: 'TOTAL XP',
  hudPassengers: 'Passengers',
  hudContainers: 'Containers',
  hudLiveEarnings: 'TOTAL INCOME',
  hudPenalty: 'Penalty',
  hudRouteKm: 'Route KM',
  hudCancelJob: 'Cancel Job',
  hudCancelHold: 'Hold %s to cancel the job',
  hudCityZone: 'CITY ZONE',
  hudClear: 'CLEAR',
  hudNoActiveCityZone: 'No active city zone',
  hudCityZoneActive: '%s active',
  hudStatusFollowRoute: 'Follow route instructions to the next station.',
  hudSubtitleStatic: 'Follow route instructions.',
  hudAssistantTitle: 'ASSISTANT',
  assistantLoading: 'Loading...',
  assistantReady: 'Ready',
  assistantTransit: 'Transit',
  assistantCancelling: 'Cancelling...',
  assistantCancelJob: 'Canceling the job',
  assistantMetroBoarding: 'Passengers boarding / leaving',
  assistantMetroReady: 'Passengers seated, ready to move',
  assistantMetroTransit: 'Metro Car',
  assistantFreightLoading: 'Container loading',
  assistantFreightReady: 'Cargo secured, ready to move',
  assistantFreightTransit: 'Freight Train',
  hudRouteComplete: 'Route complete',
  hudCommandHint: 'HUD toggle: /godhud',
  hudEditCommandHint: 'HUD edit: /godhudedit',
  hudCancelKeyLabel: '[G]',
  uiHudEditDone: 'Done',
  uiHudEditResetDefault: 'Reset to Default',
  uiHudEditScale: 'Scale',
  uiHudEditDrag: 'Drag HUD',
  closeLabel: 'Close',
  interactLabel: 'Interact',
  showInHud: 'Show in HUD',
  hideFromHud: 'Hide from HUD',
  questTooltipLabel: 'Show full quest description',
  rankDescriptions: {
    trainee: 'Entry-level certification for new metro operators. Build route knowledge and consistency.',
    junior: 'Certified operator with better pay and increased route responsibility.',
    senior: 'Experienced operator for advanced routes and stronger multipliers.',
    chief: 'Top-tier metro authority with maximum trust and premium earnings.'
  }
};

const rankAvatarByKey = {
  trainee: 'assets/traineeavatar.svg',
  junior: 'assets/junioravatar.svg',
  senior: 'assets/senioravatar.svg',
  chief: 'assets/chiefavatar.svg'
};

const assistantProgressRuntime = {
  rafId: null,
  stage: null,
  startClientAt: 0,
  durationMs: 0,
  startProgress: 0
};

const assistantNotifyRuntime = {
  timeoutId: null,
  rafId: null,
  hideAt: 0,
  durationMs: 0,
  active: false,
  loading: '',
  message: '',
  locked: false
};

const assistantDisplayState = {
  loading: '',
  message: ''
};

function setAssistantProgress(progressValue) {
  const progress = clamp(Number(progressValue || 0), 0, 100);
  const totalSegments = hudAssistantSegments.length || 4;
  const segmentProgress = (progress / 100) * totalSegments;
  hudAssistantSegments.forEach((segment, index) => {
    const fill = clamp((segmentProgress - index) * 100, 0, 100);
    setStyle(segment, 'width', `${fill}%`);
  });
}

function stopAssistantProgressAnimation() {
  if (assistantProgressRuntime.rafId) {
    cancelAnimationFrame(assistantProgressRuntime.rafId);
    assistantProgressRuntime.rafId = null;
  }
}

function stopAssistantNotifyAnimation() {
  if (assistantNotifyRuntime.timeoutId) {
    clearTimeout(assistantNotifyRuntime.timeoutId);
    assistantNotifyRuntime.timeoutId = null;
  }
  if (assistantNotifyRuntime.rafId) {
    cancelAnimationFrame(assistantNotifyRuntime.rafId);
    assistantNotifyRuntime.rafId = null;
  }
}

function hideAssistantNotify() {
  stopAssistantNotifyAnimation();
  assistantNotifyRuntime.active = false;
  assistantNotifyRuntime.loading = '';
  assistantNotifyRuntime.message = '';
  setText(hudAssistantLoading, assistantDisplayState.loading || '');
  setText(hudAssistantDesc, assistantDisplayState.message || '');
}

function showAssistantNotify(message, nType, durationMs) {
  const type = String(nType || 'inform').toLowerCase();
  const duration = Math.max(1200, Number(durationMs || 5000));
  const lowerMsg = String(message || '').toLowerCase();
  const isEarlyExit = type === 'early_exit'
    || lowerMsg.includes('early exit')
    || lowerMsg.includes('predcas')
    || lowerMsg.includes('předčas')
    || lowerMsg.includes('ukonc')
    || lowerMsg.includes('ukonč');
  stopAssistantNotifyAnimation();
  assistantNotifyRuntime.active = true;
  assistantNotifyRuntime.loading = isEarlyExit
    ? 'Early Exit'
    : (type === 'error' ? 'Penalty' : (type === 'success' ? 'Earnings' : 'Assistant'));
  assistantNotifyRuntime.message = String(message || '');
  setText(hudAssistantLoading, assistantNotifyRuntime.loading);
  setText(hudAssistantDesc, assistantNotifyRuntime.message);

  const startedAt = performance.now();
  const tick = () => {
    const elapsed = performance.now() - startedAt;
    const ratio = Math.max(0, Math.min(1, elapsed / duration));
    setAssistantProgress(ratio * 100);
    if (ratio < 1) {
      assistantNotifyRuntime.rafId = requestAnimationFrame(tick);
    } else {
      assistantNotifyRuntime.rafId = null;
    }
  };

  assistantNotifyRuntime.rafId = requestAnimationFrame(tick);
  assistantNotifyRuntime.timeoutId = window.setTimeout(hideAssistantNotify, duration);
}

function startAssistantProgressAnimation(stage, progressValue, durationMs) {
  stopAssistantProgressAnimation();
  assistantProgressRuntime.stage = String(stage || '');
  assistantProgressRuntime.durationMs = Math.max(0, Number(durationMs || 0));
  assistantProgressRuntime.startProgress = clamp(Number(progressValue || 0), 0, 100);
  assistantProgressRuntime.startClientAt = performance.now();
  setAssistantProgress(assistantProgressRuntime.startProgress);
}

function buildHudModel(data = {}) {
  const isMetro = String(data.mode || 'metro').toLowerCase() === 'metro';
  const hasSpeedLimit = data.speedLimit !== null && data.speedLimit !== undefined && Number(data.speedLimit) > 0;
  const xpValue = Number(data.gainedXp || 0);
  const assistantState = getAssistantState(data.mode, data.currentStage, data.cancelProgress);
  const assistantLoadingText = assistantNotifyRuntime.active ? assistantNotifyRuntime.loading : assistantState.loading;
  const assistantDescText = assistantNotifyRuntime.active ? assistantNotifyRuntime.message : assistantState.desc;
  assistantDisplayState.loading = assistantState.loading;
  assistantDisplayState.message = assistantState.desc;

  const hudModel = {
    title: 'METRO <span class="hud__title-accent">STATUS</span>',
    status: L('hudSubtitleStatic'),
    nextStation: String(data.nextStation || L('hudRouteComplete')),
    distance: fmtDistanceMeters(data.distanceToNext || 0),
    km: `${Number(data.currentKm || 0).toFixed(2)} / ${Number(data.targetKm || 0).toFixed(2)}`,
    total: `${Number(data.totalMileage || 0).toFixed(2)} km`,
    stops: `${data.stationCurrent ?? data.stopsDone ?? 0} / ${data.stationTotal ?? data.stopsTotal ?? 0}`,
    xp: `${xpValue}`,
    speedLimit: hasSpeedLimit ? `${Number(data.speedLimit).toFixed(0)} ${String(data.speedUnit || 'KM.')}` : L('hudNoLimit'),
    cargoLabel: isMetro ? L('hudPassengers') : L('hudContainers'),
    cargoCount: `${Number(data.cargoCount || 0)}`,
    liveEarnings: fmtMoney(data.liveEarnings || 0),
    penalty: fmtMoney(data.penaltyAmount || 0),
    timer: fmtCountdown(data.timeRemainingSec || 0),
    assistantLoading: assistantLoadingText,
    assistantDesc: assistantDescText,
    assistantProgress: Math.max(0, Math.min(100, Number(data.stageProgress || 0))),
    currentStage: String(data.currentStage || ''),
    cancelProgress: Math.max(0, Math.min(100, Number(data.cancelProgress || 0))),
    cancel: fmt(L('hudCancelHold'), String(data.cancelKey || L('hudCancelKeyLabel'))),
    cancelWidth: `${Math.max(0, Math.min(100, Number(data.cancelProgress || 0)))}%`
  };

  hudModel.signature = [
    hudModel.status,
    hudModel.nextStation,
    hudModel.distance,
    hudModel.km,
    hudModel.total,
    hudModel.stops,
    hudModel.xp,
    hudModel.speedLimit,
    hudModel.cargoLabel,
    hudModel.cargoCount,
    hudModel.liveEarnings,
    hudModel.penalty,
    hudModel.timer,
    hudModel.assistantLoading,
    hudModel.assistantDesc,
    hudModel.assistantProgress,
    hudModel.currentStage,
    hudModel.cancelProgress,
    hudModel.cancel
  ].join('|');

  return hudModel;
}

function renderHudModel(hudModel) {
  if (!hudModel || hudModel.signature === lastHudUpdateSignature) return;
  lastHudUpdateSignature = hudModel.signature;

  setHtml(hudTitle, hudModel.title);
  setText(hudStatus, hudModel.status);
  setText(hudNextStation, hudModel.nextStation);
  setText(hudDistance, hudModel.distance);
  setText(hudKm, hudModel.km);
  setText(hudTotal, hudModel.total);
  setText(hudStops, hudModel.stops);
  setText(hudXp, hudModel.xp);
  setText(hudSpeedLimit, hudModel.speedLimit);
  setText(hudCargoLabel, hudModel.cargoLabel);
  setText(hudCargoCount, hudModel.cargoCount);
  setText(hudLiveEarnings, hudModel.liveEarnings);
  setText(hudPenalty, hudModel.penalty);
  setText(hudTimerBg, hudModel.timer);
  setText(hudTimer, hudModel.timer);
  setText(hudAssistantLoading, hudModel.assistantLoading);
  setText(hudAssistantDesc, hudModel.assistantDesc);

  if (assistantNotifyRuntime.active) {
    stopAssistantProgressAnimation();
  } else if (hudModel.cancelProgress > 0) {
    stopAssistantProgressAnimation();
    setAssistantProgress(hudModel.cancelProgress);
  } else {
    setAssistantProgress(hudModel.assistantProgress);
  }

  setText(hudCancel, hudModel.cancel);
  setStyle(hudCancelProgress, 'width', hudModel.cancelWidth);
}

function queueHudRender(hudModel) {
  pendingHudModel = hudModel;
  if (hudRenderQueued) return;
  hudRenderQueued = true;
  requestAnimationFrame(() => {
    hudRenderQueued = false;
    const model = pendingHudModel;
    pendingHudModel = null;
    renderHudModel(model);
  });
}

function L(key) {
  return panelData?.ui?.[key] ?? fallbackLocale[key];
}

function fmt(template, ...values) {
  if (typeof template !== 'string') return '';
  let index = 0;
  return template.replace(/%s/g, () => String(values[index++] ?? ''));
}

function setAppVisible(visible) {
  if (!app) return;
  if (visible) {
    app.classList.add('active');
    app.style.display = 'block';
    app.style.opacity = '';
    app.style.pointerEvents = '';
    app.style.visibility = 'visible';
    document.body.classList.add('ui-panel-open');
  } else {
    app.classList.remove('active');
    app.style.display = 'none';
    app.style.opacity = '';
    app.style.pointerEvents = '';
    app.style.visibility = '';
    document.body.classList.remove('ui-panel-open');
  }
}

window.setHudVisible = function setHudVisible(visible) {
  if (!hud) return;
  hud.classList.toggle('is-hidden', !visible);
  hud.style.display = visible ? '' : 'none';
};

function applyHudLayout(layout = {}) {
  if (!hud) return;
  const minScale = Number(hudEditorConfig.scale.minPct || 75) / 100;
  const maxScale = Number(hudEditorConfig.scale.maxPct || 140) / 100;
  hudLayout = {
    leftPct: Number(layout.leftPct ?? hudLayout.leftPct ?? 50.0),
    topPct: Number(layout.topPct ?? hudLayout.topPct ?? 1.35),
    scale: Math.max(minScale, Math.min(maxScale, Number(layout.scale ?? hudLayout.scale ?? 0.92))),
    hiddenItems: typeof layout.hiddenItems === 'object' && layout.hiddenItems ? layout.hiddenItems : (hudLayout.hiddenItems || {})
  };
  if (hudLayout.leftPct <= 5 && hudLayout.topPct >= 20) {
    hudLayout.leftPct = defaultHudLayout.leftPct;
    hudLayout.topPct = defaultHudLayout.topPct;
    hudLayout.scale = defaultHudLayout.scale;
  }
  hud.style.left = `${hudLayout.leftPct}%`;
  hud.style.top = `${hudLayout.topPct}%`;
  hud.style.setProperty('--hud-scale', String(hudLayout.scale));
  hud.style.transform = `translateX(-50%) scale(${hudLayout.scale})`;
  hud.style.transformOrigin = 'top center';
  if (hudScaleRange) hudScaleRange.value = String(Math.round(hudLayout.scale * 100));
  applyHudVisibility();
}

function applyHudEditorConfig(data = {}) {
  const incomingDefaults = data.defaultLayout || {};
  const incomingScale = data.scale || {};
  const incomingLabels = data.labels || {};

  defaultHudLayout.leftPct = Number(incomingDefaults.leftPct ?? defaultHudLayout.leftPct ?? 1.55);
  defaultHudLayout.topPct = Number(incomingDefaults.topPct ?? defaultHudLayout.topPct ?? 30.0);
  defaultHudLayout.scale = Number(incomingDefaults.scale ?? defaultHudLayout.scale ?? 1.0);

  hudEditorConfig.scale.minPct = Number(incomingScale.minPct ?? hudEditorConfig.scale.minPct ?? 75);
  hudEditorConfig.scale.maxPct = Number(incomingScale.maxPct ?? hudEditorConfig.scale.maxPct ?? 140);
  hudEditorConfig.scale.stepPct = Number(incomingScale.stepPct ?? hudEditorConfig.scale.stepPct ?? 1);
  hudEditorConfig.labels = { ...hudEditorConfig.labels, ...incomingLabels };

  if (hudScaleRange) {
    hudScaleRange.min = String(hudEditorConfig.scale.minPct);
    hudScaleRange.max = String(hudEditorConfig.scale.maxPct);
    hudScaleRange.step = String(hudEditorConfig.scale.stepPct);
  }

  if (hudEditClose) hudEditClose.textContent = hudEditorConfig.labels.done || fallbackLocale.uiHudEditDone;
  if (hudEditReset) hudEditReset.textContent = hudEditorConfig.labels.resetDefault || fallbackLocale.uiHudEditResetDefault;
  if (hudScaleLabel) hudScaleLabel.textContent = hudEditorConfig.labels.scale || fallbackLocale.uiHudEditScale;
  if (hudDragHandle) hudDragHandle.textContent = hudEditorConfig.labels.drag || fallbackLocale.uiHudEditDrag;
  if (hudCommandHint) hudCommandHint.textContent = hudEditorConfig.labels.commandHint || fallbackLocale.hudCommandHint;
  if (hudEditCommandHint) hudEditCommandHint.textContent = hudEditorConfig.labels.editCommandHint || fallbackLocale.hudEditCommandHint;
}

async function saveHudLayout() {
  await nui('godtrain:saveHudLayout', hudLayout);
}

function applyHudVisibility() {
  hudItems.forEach(item => {
    const key = item.dataset.hudItem;
    const hidden = key === 'assistant' ? false : !!hudLayout.hiddenItems?.[key];
    item.classList.toggle('hud-item--hidden', hidden);
    item.classList.toggle('hud-item--edit-visible', hudEditMode && hidden);
    item.classList.toggle('is-hidden', hidden && !hudEditMode);
    item.style.display = hidden && !hudEditMode ? 'none' : '';
    const toggle = item.querySelector('.hud-item-visibility-toggle');
    if (toggle) {
      toggle.classList.toggle('is-off', hidden);
      toggle.setAttribute('aria-pressed', hidden ? 'true' : 'false');
      toggle.title = hidden ? L('showInHud') : L('hideFromHud');
    }
  });
}

function buildHudToggleControls() {
  hudItems.forEach(item => {
    const key = item.dataset.hudItem;
    let toggle = item.querySelector('.hud-item-visibility-toggle');
    if (toggle) return;
    toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'hud-item-visibility-toggle';
    toggle.innerHTML = '<span class="hud-item-visibility-toggle__icon" aria-hidden="true"></span>';
    toggle.addEventListener('pointerdown', event => {
      event.preventDefault();
      event.stopPropagation();
    });
    toggle.addEventListener('click', async event => {
      event.preventDefault();
      event.stopPropagation();
      hudLayout.hiddenItems[key] = !hudLayout.hiddenItems?.[key];
      applyHudVisibility();
      await saveHudLayout();
    });
    item.appendChild(toggle);
  });
}

function removeHudToggleControls() {
  hudItems.forEach(item => {
    item.querySelectorAll('.hud-item-visibility-toggle').forEach(toggle => toggle.remove());
  });
}

function setHudEditMode(enabled) {
  hudEditMode = !!enabled;
  if (hudLayout?.hiddenItems) {
    hudLayout.hiddenItems.assistant = false;
  }
  hudEditBar?.classList.toggle('is-hidden', !hudEditMode);
  hudDragHandle?.classList.add('is-hidden');
  hud?.classList.toggle('hud--edit', hudEditMode);
  document.body?.classList?.toggle('ui-panel-open', hudEditMode);
  if (document.body) {
    document.body.style.pointerEvents = hudEditMode ? 'all' : '';
  }
  if (hud) {
    hud.style.pointerEvents = hudEditMode ? 'all' : '';
  }
  if (hudEditBar) {
    hudEditBar.style.pointerEvents = hudEditMode ? 'all' : '';
  }
  if (hudDragHandle) hudDragHandle.style.pointerEvents = 'none';
  if (hudCommandHint) {
    hudCommandHint.textContent = L('hudCommandHint');
  }
  if (hudEditCommandHint) {
    hudEditCommandHint.textContent = L('hudEditCommandHint');
  }
  removeHudToggleControls();
  applyHudVisibility();
}

function resetUiState() {
  hardResetTransparency();
  setAppVisible(false);
  window.setHudVisible(false);
  if (builtInTextUI) {
    builtInTextUI.classList.add('is-hidden');
    builtInTextUI.style.display = 'none';
  }
  paymentModal?.classList.add('is-hidden');
  questModal?.classList.add('is-hidden');
  selectedRankForPayment = null;
}

async function nui(eventName, body = {}) {
  const response = await fetch(`https://${GetParentResourceName()}/${eventName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  return response.json();
}

async function copyTextToClipboard(text) {
  const value = String(text || '');
  if (!value) return { ok: false, message: 'Empty text' };

  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return { ok: true, message: '' };
    }
  } catch (err) {
    // fallback below
  }

  try {
    const textArea = document.createElement('textarea');
    textArea.value = value;
    textArea.setAttribute('readonly', '');
    textArea.style.position = 'fixed';
    textArea.style.opacity = '0';
    textArea.style.pointerEvents = 'none';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    const copied = document.execCommand('copy');
    document.body.removeChild(textArea);
    return copied ? { ok: true, message: '' } : { ok: false, message: 'execCommand(copy) failed' };
  } catch (err) {
    return { ok: false, message: String(err?.message || err || 'Copy failed') };
  }
}

function fmtMoney(value) {
  return `$${Number(value || 0).toLocaleString()}`;
}

function fmtDistanceMeters(value) {
  const meters = Number(value || 0);
  if (meters >= 1000) return `${(meters / 1000).toFixed(2)} km`;
  return `${meters.toFixed(0)} m`;
}

function fmtCountdown(totalSec) {
  const sec = Math.max(0, Math.floor(Number(totalSec || 0)));
  const mm = String(Math.floor(sec / 60)).padStart(2, '0');
  const ss = String(sec % 60).padStart(2, '0');
  return `${mm}:${ss}`;
}

function getAssistantState(mode, stage, cancelProgress) {
  const isMetro = String(mode || 'metro').toLowerCase() === 'metro';
  const currentStage = String(stage || '').toLowerCase();
  const canceling = Number(cancelProgress || 0) > 0;

  if (canceling) {
    return { loading: L('assistantCancelling'), desc: L('assistantCancelJob') };
  }

  if (isMetro) {
    if (currentStage === 'boarding') return { loading: L('assistantLoading'), desc: L('assistantMetroBoarding') };
    if (currentStage === 'ready') return { loading: L('assistantReady'), desc: L('assistantMetroReady') };
    return { loading: L('assistantTransit'), desc: L('assistantMetroTransit') };
  }

  if (currentStage === 'loading') return { loading: L('assistantLoading'), desc: L('assistantFreightLoading') };
  if (currentStage === 'ready') return { loading: L('assistantReady'), desc: L('assistantFreightReady') };
  return { loading: L('assistantTransit'), desc: L('assistantFreightTransit') };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function toLevelData(player) {
  const levelStep = getXpLevelStep();
  const xpPerKm = Number(panelData?.ui?.xpPerKm || 12);
  const xpPerRoute = Number(panelData?.ui?.xpPerRoute || 70);
  if (typeof player?.xp === 'number' && typeof player?.levelProgress === 'number') {
    const xp = Number(player.xp || 0);
    const level = Math.max(1, Number(player.level || 1));
    const base = (level - 1) * levelStep;
    const current = Math.max(0, xp - base);
    const needed = levelStep;
    const remaining = Math.max(0, needed - current);
    return {
      progress: Number(player.levelProgress || 0),
      xp,
      current,
      needed,
      remaining,
      nextLevel: level + 1
    };
  }

  const totalKm = Number(player?.totalKm || 0);
  const routes = Number(player?.completedRoutes || 0);

  const xp = Math.floor((totalKm * xpPerKm) + (routes * xpPerRoute));
  const level = Math.max(1, Math.floor(xp / levelStep) + 1);
  const base = (level - 1) * levelStep;
  const next = level * levelStep;
  const current = xp - base;
  const needed = Math.max(1, next - base);
  const progress = clamp((current / needed) * 100, 0, 100);

  return { progress, xp, current, needed, remaining: Math.max(0, needed - current), nextLevel: level + 1 };
}

function getNextRankKey(ranks) {
  const activeIndex = ranks.findIndex(rank => rank?.active === true);
  for (let i = Math.max(activeIndex + 1, 0); i < ranks.length; i += 1) {
    if (!ranks[i]?.unlocked) return String(ranks[i]?.key || '');
  }
  return '';
}

function normalizeRouteType(value) {
  const text = String(value || '').toLowerCase();
  if (text.includes('freight') || text.includes('train')) return 'train';
  return 'metro';
}

function currentProfileType() {
  const profileType = String(panelData?.ui?.profileType || '').toLowerCase();
  return profileType === 'metro' ? 'metro' : 'train';
}

function getRoutesForCurrentProfile() {
  const routes = Array.isArray(panelData?.routes) ? panelData.routes : [];
  const profileType = currentProfileType();
  return routes.filter(route => normalizeRouteType(route.category || route.trainType) === profileType);
}

function refreshStaticTexts() {
  const signature = [
    L('companyTitleMain'),
    L('companyTitleSub'),
    L('companyDescription'),
    L('buyLicenseTitle'),
    L('buyLicenseHint'),
    L('xpLabel'),
    L('buttonQuests'),
    L('hudCommandHint'),
    L('hudEditCommandHint'),
    L('questTitle'),
    L('questSubtitle'),
    L('hudTitle'),
    L('hudNextStation'),
    L('hudDistance'),
    L('hudStops'),
    L('hudSpeedLimit'),
    L('hudLiveEarnings'),
    L('hudPenalty'),
    L('hudRouteKm'),
    L('hudTotal'),
    L('hudXp'),
    L('hudCancelJob'),
    L('closeLabel'),
    L('interactLabel'),
    L('showInHud'),
    L('hideFromHud'),
    L('questTooltipLabel')
  ].join('|');

  if (lastStaticTextSignature !== signature) {
    lastStaticTextSignature = signature;
    setText(companyTitleMain, L('companyTitleMain'));
    setText(companyTitleSub, L('companyTitleSub'));
    setText(companyGlow, `${L('companyTitleMain')} ${L('companyTitleSub')}`);
    setText(companyDesc, L('companyDescription'));
    setText(buyLicenseTitle, L('buyLicenseTitle'));
    setText(buyLicenseHint, L('buyLicenseHint'));
    setText(xpLabel, L('xpLabel'));
    setText(questsBtn, L('buttonQuests'));
    setText(hudCommandHint, L('hudCommandHint'));
    setText(hudEditCommandHint, L('hudEditCommandHint'));
    if (closeQuest) closeQuest.setAttribute('aria-label', L('closeLabel'));
    if (builtInTextUIText) setText(builtInTextUIText, L('interactLabel'));
    setText(paymentModalHeader, L('buyLicenseTitle'));
    setText(payCash, L('payCash'));
    setText(payBank, L('payBank'));
    setText(questModalTitle, L('questTitle'));
    setText(questModalSubtitle, L('questSubtitle'));
    setHtml(hudTitle, 'METRO <span class="hud__title-accent">STATUS</span>');
    setText(hudStatus, L('hudSubtitleStatic'));
    setText(hudNextStationLabel, L('hudNextStation'));
    setText(hudDistanceLabel, L('hudDistance'));
    setText(hudStopsLabel, L('hudStops'));
    setText(hudSpeedLimitLabel, L('hudSpeedLimit'));
    setText(hudLiveEarningsLabel, L('hudLiveEarnings'));
    setText(hudPenaltyLabel, L('hudPenalty'));
    setText(hudRouteKmLabel, L('hudRouteKm'));
    setText(hudTotalLabel, L('hudTotal'));
    setText(hudXpLabel, L('hudXp'));
    setText(hudCancelLabel, L('hudCancelJob'));
    const assistantTitle = document.querySelector('.hud-assistant__title');
    if (assistantTitle) setText(assistantTitle, L('hudAssistantTitle'));
    document.querySelectorAll('.quest-panel__info').forEach(el => {
      el.setAttribute('aria-label', L('questTooltipLabel'));
    });
    applyHudVisibility();
  }

  const avatarSignature = `${panelData?.ui?.avatarImage || ''}|${panelData?.ui?.avatarFallback || 'assets/avatar.png'}`;
  if (avatarSignature !== lastAvatarSignature) {
    lastAvatarSignature = avatarSignature;
    applyAvatarImage(panelData?.ui?.avatarImage, panelData?.ui?.avatarFallback || 'assets/avatar.png');
  }
}

function updateQuestButtonState() {
  if (!questsBtn) return;
  const quests = Array.isArray(panelData?.quests) ? panelData.quests : [];
  const claimable = quests.filter(q => !q.claimed && q.completed).length;
  const base = L('buttonQuests');
  questsBtn.textContent = claimable > 0 ? `${base} (${claimable})` : base;
}

function updateSegmentedRankBar(progressValue) {
  if (!rankBar) return;

  rankBar.dataset.progress = progressValue.toFixed(2);
  rankBar.setAttribute('aria-valuenow', String(progressValue));

  rankBarSegments.forEach((segment, index) => {
    const segmentProgress = Math.max(0, Math.min(1, (progressValue - index * 25) / 25));
    const fillPercent = Math.round(segmentProgress * 100);
    segment.style.setProperty('--fill', `${fillPercent}%`);
    segment.classList.toggle('is-filled', fillPercent > 0);
  });
}

function updatePlayerHeader() {
  const player = panelData?.player || {};
  const levelData = toLevelData(player);
  const defaultRankLabel = panelData?.ranks?.find(rank => String(rank?.key || '').toLowerCase() === 'trainee')?.label || 'Trainee';
  if (playerName) playerName.textContent = String(player.name || '');
  if (playerRank) playerRank.textContent = String(player.rank || defaultRankLabel).toUpperCase();
  if (playerXp) playerXp.textContent = String(levelData.xp || 0);
  if (xpText) xpText.textContent = `${levelData.progress.toFixed(2)}%`;

  updateSegmentedRankBar(levelData.progress);
}

function calcUnlockProgress(rank, player) {
  const req = rank?.requirements || {};
  const current = {
    km: Number(player?.totalKm || 0),
    routes: Number(player?.completedRoutes || 0),
    accuracy: Number(player?.accuracy || 0),
    level: Number(player?.level || 1)
  };

  const chunks = [];

  const kmReq = Number(req.minKm || 0);
  if (kmReq > 0) chunks.push(clamp((current.km / kmReq) * 100, 0, 100));

  const routesReq = Number(req.minRoutes || 0);
  if (routesReq > 0) chunks.push(clamp((current.routes / routesReq) * 100, 0, 100));

  const accuracyReq = Number(req.minAccuracy || 0);
  if (accuracyReq > 0) chunks.push(clamp((current.accuracy / accuracyReq) * 100, 0, 100));

  const levelReq = Number(req.minLevel || 0);
  if (levelReq > 0) chunks.push(clamp((current.level / levelReq) * 100, 0, 100));

  if (!chunks.length) return 100;
  const avg = chunks.reduce((a, b) => a + b, 0) / chunks.length;
  return clamp(avg, 0, 100);
}

function renderLicenseTabs() {
  if (!licenseTabs) return;
  licenseTabs.innerHTML = '';

  const ranks = Array.isArray(panelData?.ranks) ? panelData.ranks : [];
  const nextRankKey = getNextRankKey(ranks);
  ranks.forEach(rank => {
    const buyable = !rank.unlocked && !!rank.requirementsMet;
    const isNext = !rank.active && String(rank.key || '') === nextRankKey;
    const showUnlockedStyle = rank.active === true;
    const stateLabel = rank.active
      ? (panelData?.ui?.rankStateActive || fallbackLocale.rankStateActive)
      : (isNext
        ? (panelData?.ui?.rankStateNext || fallbackLocale.rankStateNext)
        : (panelData?.ui?.rankStateLocked || fallbackLocale.rankStateLocked));
    const item = document.createElement('div');
    item.className = `rank-item ${rank.active ? 'rank-item--active' : ''} ${showUnlockedStyle ? 'rank-item--unlocked' : ''} ${buyable ? 'rank-item--buyable' : ''} ${isNext ? 'rank-item--next' : ''} ${(!rank.active && !buyable && !isNext) ? 'rank-item--locked' : ''}`;
    item.innerHTML = `
      <span class="rank-item__label">${String(rank.label || rank.key || 'Rank').toUpperCase()}</span>
    `;

    licenseTabs.appendChild(item);
  });
}

function ensureSelectedRoute() {
  const routes = getRoutesForCurrentProfile();
  if (!routes.length) {
    selectedRouteId = null;
    return;
  }

  if (!routes.some(route => Number(route.id) === Number(selectedRouteId))) {
    selectedRouteId = Number(routes[0].id);
  }
}

function buildPaymentText(amount) {
  const tpl = L('modalPaymentText');
  return fmt(tpl, `<span class="trainer-modal__amount">${amount}</span>`);
}

function renderRankCards() {
  const ranks = Array.isArray(panelData?.ranks) ? panelData.ranks : [];
  const rankDescriptions = panelData?.ui?.rankDescriptions || fallbackLocale.rankDescriptions;
  const player = panelData?.player || {};
  const nextRankKey = getNextRankKey(ranks);
  const activeRoutes = getRoutesForCurrentProfile();
  const selectedRoute = Array.isArray(activeRoutes)
    ? activeRoutes.find(route => Number(route?.id) === Number(selectedRouteId))
    : null;

  let baseStationEarning = 0;
  let baseRouteBonus = 0;

  if (selectedRoute && selectedRoute.stopReward != null) {
    baseStationEarning = Number(selectedRoute.stopReward) || 0;
  } else if (panelData && panelData.ui && panelData.ui.stationEarningBase != null) {
    baseStationEarning = Number(panelData.ui.stationEarningBase) || 0;
  } else if (panelData && Array.isArray(panelData.routes) && panelData.routes[0] && panelData.routes[0].stopReward != null) {
    baseStationEarning = Number(panelData.routes[0].stopReward) || 0;
  }

  if (selectedRoute && selectedRoute.completionReward != null) {
    baseRouteBonus = Number(selectedRoute.completionReward) || 0;
  } else if (panelData && panelData.ui && panelData.ui.routeBonusBase != null) {
    baseRouteBonus = Number(panelData.ui.routeBonusBase) || 0;
  } else if (panelData && Array.isArray(panelData.routes) && panelData.routes[0] && panelData.routes[0].completionReward != null) {
    baseRouteBonus = Number(panelData.routes[0].completionReward) || 0;
  }

  rankCards.forEach((card, index) => {
    const rank = ranks[index];
    if (!rank) {
      card.style.display = 'none';
      return;
    }

    card.style.display = '';

    const key = String(rank.key || '').toLowerCase();
    const unlocked = rank.unlocked === true;
    const active = rank.active === true;
    const isNext = !active && key === nextRankKey;
    const cardState = active ? 'active' : (isNext ? 'next' : 'closed');

    card.dataset.state = cardState;

    const refs = rankCardRefs[index] || {};
    const titleEl = refs.titleEl;
    const descEl = refs.descEl;
    const avatarEl = refs.avatarEl;
    const metricEls = refs.metricEls || [];
    const metricLabelEls = refs.metricLabelEls || [];
    const unlockLabelEl = refs.unlockLabelEl;
    const unlockValueEl = refs.unlockValueEl;
    const unlockFillEl = refs.unlockFillEl;
    const unlockWrapEl = refs.unlockWrapEl;
    const stateEl = refs.stateEl;

    setText(titleEl, String(rank.label || key || 'RANK').toUpperCase());
    setText(descEl, rankDescriptions[key] || fallbackLocale.rankDescriptions[key] || '');
    if (avatarEl && rankAvatarByKey[key] && avatarEl.src !== rankAvatarByKey[key]) avatarEl.src = rankAvatarByKey[key];
    setText(metricLabelEls[0], L('rankStationEarning'));
    setText(metricLabelEls[1], L('rankRouteBonus'));
    setText(unlockLabelEl, L('rankUnlockProgress'));

    const stationEarning = Math.round(Number(rank.multiplier || 1) * baseStationEarning);
    const routeBonus = Math.round(Number(rank.multiplier || 1) * baseRouteBonus);
    if (metricEls[0]) {
      setText(metricEls[0], `${stationEarning}$`);
      metricEls[0].classList.toggle('rank-card-metric-value--locked', !active);
    }
    if (metricEls[1]) {
      setText(metricEls[1], `${routeBonus}$`);
      metricEls[1].classList.toggle('rank-card-metric-value--locked', !active);
    }

    const img = refs.img;
    if (img) {
      const nextImg = active ? 'assets/openned-rank.png' : `assets/closed-rank${Math.min(index + 1, 4)}.png`;
      if (img.src !== nextImg) img.src = nextImg;
    }

    if (unlockWrapEl) {
      unlockWrapEl.style.display = isNext ? '' : 'none';
    }
    if (stateEl) {
      setText(stateEl, active ? (panelData?.ui?.rankStateActive || fallbackLocale.rankStateActive) : (isNext ? (panelData?.ui?.rankStateNext || fallbackLocale.rankStateNext) : (panelData?.ui?.rankStateLocked || fallbackLocale.rankStateLocked)));
    }

    const unlockProgress = unlocked ? 100 : calcUnlockProgress(rank, player);
    setText(unlockValueEl, `${Math.round(unlockProgress)}%`);
    setStyle(unlockFillEl, 'width', `${unlockProgress}%`);

    const button = rankButtons[index];
    if (button) {
      const canBuy = !unlocked && !!rank.requirementsMet;
      if (active) {
        button.textContent = fmt(L('rankButtonActive'), rank.label);
      } else if (isNext) {
        button.textContent = canBuy ? L('rankButtonBuy') : L('rankButtonLocked');
      } else {
        button.textContent = L('rankButtonLocked');
      }

      button.classList.toggle('rank-button--active', active || canBuy);
      button.classList.toggle('rank-button--muted', !active && !canBuy);
      button.disabled = !active && !canBuy;
      button.onclick = async () => {
        if (active) {
          await startRoute(rank.key);
          return;
        }

        if (!rank.requirementsMet) {
          return;
        }

        selectedRankForPayment = rank;
        setHtml(paymentText, buildPaymentText(fmtMoney(rank.unlockPrice)));
        paymentModal.classList.remove('is-hidden');
      };
    }
  });
}

function questTypeClass(quest) {
  if (quest.claimed || quest.claimPending) return 'quest-panel--gray';
  if (quest.completed) return 'quest-panel';
  return 'quest-panel--red';
}

function questIcon(quest) {
  if (quest.claimed || quest.claimPending) return 'assets/questicongray.svg';
  if (quest.completed) return 'assets/questicon.svg';
  return 'assets/questiconred.svg';
}

function questMoneyIcon(quest) {
  if (quest.claimed || quest.claimPending) return 'assets/moneygray.svg';
  if (quest.completed) return 'assets/moneyg.svg';
  return 'assets/moneyr.svg';
}

function periodLabel(period) {
  if (String(period).toLowerCase() === 'weekly') return L('questPeriodWeekly');
  return L('questPeriodDaily');
}

function escapeHtmlAttr(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderQuests() {
  if (!questList) return;
  questList.innerHTML = '';

  const quests = Array.isArray(panelData?.quests) ? panelData.quests : [];

  if (!quests.length) {
    const empty = document.createElement('div');
    empty.className = 'quest-panel quest-panel--gray';
    empty.innerHTML = `<div class="quest-panel__text" style="left:20px">${L('noQuests')}</div>`;
    questList.appendChild(empty);
    return;
  }

  quests.forEach(quest => {
    const description = String(quest.description || '');
    const tooltipText = escapeHtmlAttr(description);
    const progressRaw = Number(quest.progress || 0);
    const targetRaw = Math.max(1, Number(quest.target || 1));
    const progressPct = clamp((progressRaw / targetRaw) * 100, 0, 100);

    const item = document.createElement('div');
    item.className = `quest-panel ${questTypeClass(quest)}`;
    item.innerHTML = `
      <img class="quest-panel__icon" src="${questIcon(quest)}" alt="" />
      <div class="quest-panel__text">${String(quest.label || quest.id || 'Quest')}</div>
      <div class="quest-panel__desc">${description}</div>
      <div class="quest-panel__info" data-tooltip="${tooltipText}" aria-label="${escapeHtmlAttr(L('questTooltipLabel'))}">i</div>
      <div class="quest-panel__progress"><span class="quest-panel__progress-fill" style="width:${progressPct.toFixed(2)}%"></span></div>
      <div class="quest-panel__percent">%${progressPct.toFixed(0)}</div>
      <div class="quest-panel__badge"><span class="quest-panel__badge-text">${Number(progressRaw).toFixed(2)} / ${targetRaw}</span></div>
      <img class="quest-panel__reward-icon" src="${questMoneyIcon(quest)}" alt="" />
      <div class="quest-panel__reward">${fmtMoney(quest.reward)}</div>
    `;
    const info = item.querySelector('.quest-panel__info');
    if (info) {
      info.addEventListener('click', event => event.stopPropagation());
      info.addEventListener('mousedown', event => event.stopPropagation());
    }

    if (!quest.claimed && quest.completed) {
      item.style.cursor = 'pointer';
      item.addEventListener('click', () => {
        if (quest.claimPending) return;
        questClaimQueue.push({ quest, questId: quest.id, profileType: currentProfileType() });
        processQuestClaimQueue();
      });
    }

    questList.appendChild(item);
  });
}

function renderAll() {
  if (!panelData) return;
  ensureSelectedRoute();
  refreshStaticTexts();
  updatePlayerHeader();
  renderLicenseTabs();
  renderRankCards();
  renderQuests();
  updateQuestButtonState();
}

function queueRenderAll() {
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => {
    renderQueued = false;
    renderAll();
  });
}

async function startRoute(rankKey) {
  if (selectedRouteId === null || selectedRouteId === undefined) {
    return;
  }

  const result = await nui('godtrain:startRoute', {
    routeId: Number(selectedRouteId),
    rankKey
  });

  if (!result?.ok) {
    return;
  }

  setAppVisible(false);
  paymentModal.classList.add('is-hidden');
  questModal.classList.add('is-hidden');
  await nui('godtrain:close', {});
}

async function buyLicense(account) {
  if (!selectedRankForPayment) return;

  const result = await nui('godtrain:buyLicense', {
    rankKey: selectedRankForPayment.key,
    account,
    profileType: currentProfileType()
  });

  if (result.ok && result.panel) {
    panelData = result.panel;
    selectedRankForPayment = null;
    paymentModal.classList.add('is-hidden');
    queueRenderAll();
  }
}

async function closePanel() {
  setAppVisible(false);
  paymentModal.classList.add('is-hidden');
  questModal.classList.add('is-hidden');
  selectedRankForPayment = null;
  await nui('godtrain:close', {});
}

questsBtn?.addEventListener('click', () => questModal.classList.remove('is-hidden'));
closeQuest?.addEventListener('click', () => questModal.classList.add('is-hidden'));
payCash?.addEventListener('click', () => buyLicense('cash'));
payBank?.addEventListener('click', () => buyLicense('bank'));
hudEditClose?.addEventListener('click', async () => {
  await saveHudLayout();
  setHudEditMode(false);
  await nui('godtrain:closeHudEdit', {});
});
hudEditReset?.addEventListener('click', async () => {
  hudLayout = {
    leftPct: defaultHudLayout.leftPct,
    topPct: defaultHudLayout.topPct,
    scale: defaultHudLayout.scale,
    hiddenItems: {}
  };
  applyHudLayout(hudLayout);
  await saveHudLayout();
});
hudScaleRange?.addEventListener('input', () => {
  const minScale = Number(hudEditorConfig.scale.minPct || 75) / 100;
  const maxScale = Number(hudEditorConfig.scale.maxPct || 140) / 100;
  hudLayout.scale = Math.max(minScale, Math.min(maxScale, Number(hudScaleRange.value) / 100));
  applyHudLayout(hudLayout);
});
hudEditBar?.addEventListener('pointerdown', event => event.stopPropagation());
hudEditBar?.querySelectorAll('button, input, label').forEach(node => {
  node.addEventListener('pointerdown', event => event.stopPropagation());
});
function beginHudDrag(event) {
  if (!hudEditMode) return;
  const target = event.target;
  if (target && target.closest && target.closest('#hudEditBar, .hud-item-visibility-toggle, button, input, label, a')) return;
  event.preventDefault();
  event.stopPropagation();
  hudDragState = {
    startX: event.clientX,
    startY: event.clientY,
    leftPct: hudLayout.leftPct,
    topPct: hudLayout.topPct
  };
  hud?.setPointerCapture?.(event.pointerId);
}

hudDragHandle?.addEventListener('pointerdown', beginHudDrag);
hud?.addEventListener('pointerdown', beginHudDrag);
window.addEventListener('pointermove', event => {
  if (!hudEditMode || !hudDragState) return;
  const dxPct = ((event.clientX - hudDragState.startX) / window.innerWidth) * 100;
  const dyPct = ((event.clientY - hudDragState.startY) / window.innerHeight) * 100;
  hudLayout.leftPct = Math.max(0, Math.min(85, hudDragState.leftPct + dxPct));
  hudLayout.topPct = Math.max(0, Math.min(85, hudDragState.topPct + dyPct));
  applyHudLayout(hudLayout);
});
window.addEventListener('pointerup', async () => {
  if (!hudDragState) return;
  hudDragState = null;
  await saveHudLayout();
});

paymentModal?.addEventListener('click', event => {
  if (event.target && event.target.closest('[data-close="modal"]')) {
    paymentModal.classList.add('is-hidden');
  }
});

questModal?.addEventListener('click', event => {
  if (event.target && event.target.closest('[data-close="modal"]')) {
    questModal.classList.add('is-hidden');
  }
});

window.addEventListener('keydown', async event => {
  if (event.key === 'Escape') {
    setHudBackgrounded(true);
  }
  if (event.key === 'Escape' && app && app.style.display !== 'none') {
    await closePanel();
  }
});

window.addEventListener('message', event => {
  const msg = event.data;
  if (!msg || !msg.action) return;

  if (msg.action === 'forceHide') {
    panelData = null;
    selectedRouteId = null;
    selectedRankForPayment = null;
    resetUiState();
    return;
  }

  if (msg.action === 'open' || msg.action === 'openPanel') {
    if (msg.data) {
      panelData = msg.data;
      setAppVisible(true);
      paymentModal?.classList.add('is-hidden');
      questModal?.classList.add('is-hidden');
      selectedRankForPayment = null;
      queueRenderAll();
    }
    return;
  }

  if (msg.action === 'updatePanel') {
    panelData = msg.data;
    queueRenderAll();
    return;
  }

  if (msg.action === 'assistantNotify') {
    showAssistantNotify(msg.message || '', msg.type || 'inform', msg.duration || 5000);
    return;
  }

  if (msg.action === 'setHudVisible') {
    (window.setHudVisible || function(visible) {
      if (!hud) return;
      if (visible) setHudBackgrounded(false);
      hud.classList.toggle('is-hidden', !visible);
      hud.style.display = visible ? '' : 'none';
    })(!!msg.visible);
    return;
  }

  if (msg.action === 'applyHudLayout') {
    applyHudLayout(msg.data || {});
    return;
  }

  if (msg.action === 'setHudEditorConfig') {
    applyHudEditorConfig(msg.data || {});
    return;
  }

  if (msg.action === 'setHudEditMode') {
    setHudEditMode(!!msg.enabled);
    return;
  }

  if (msg.action === 'copyHudEditorConfig') {
    const snippet = String(msg?.data?.snippet || '');
    if (snippet) {
      console.log(`[godtrain][HUD COPY]\n${snippet}`);
    }
    copyTextToClipboard(snippet)
      .then(result => nui('godtrain:hudEditCopyResult', {
        ok: !!result.ok,
        message: String(result.message || ''),
        snippet
      }))
      .catch(err => nui('godtrain:hudEditCopyResult', {
        ok: false,
        message: String(err?.message || err || 'Unknown copy error'),
        snippet
      }));
    return;
  }

  if (msg.action === 'builtInTextUI') {
    const visible = !!msg.visible;
    if (builtInTextUI) {
      builtInTextUI.classList.toggle('is-hidden', !visible);
      builtInTextUI.style.display = visible ? '' : 'none';
    }
    if (visible && builtInTextUIText) {
      const rawText = String(msg.text || '');
      const keyMatch = rawText.match(/^\s*(\[[^\]]+\])\s*(.*)$/);
      if (keyMatch) {
        if (builtInTextUIKey) builtInTextUIKey.textContent = keyMatch[1];
        builtInTextUIText.textContent = keyMatch[2] || '';
      } else {
        if (builtInTextUIKey) builtInTextUIKey.textContent = '[E]';
        builtInTextUIText.textContent = rawText;
      }
    }
    return;
  }

  if (msg.action === 'updateHud') {
    setHudBackgrounded(false);
    queueHudRender(buildHudModel(msg.data || {}));
  }
});

window.addEventListener('blur', () => {
  if (app?.classList?.contains('active')) return;
  hardResetTransparency();
  setAppVisible(false);
  if (builtInTextUI) {
    builtInTextUI.classList.add('is-hidden');
    builtInTextUI.style.display = 'none';
  }
  paymentModal?.classList.add('is-hidden');
  questModal?.classList.add('is-hidden');
  selectedRankForPayment = null;
});

window.addEventListener('beforeunload', () => {
  resetUiState();
});

resetUiState();
applyHudLayout();
