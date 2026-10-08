import { createHash, createSign, randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import http2 from 'node:http2'
import type { Pool } from 'pg'

export const GROUP_WINDOW_MS = 2 * 60 * 1000

export const notificationKinds = ['invite', 'weekly_plan', 'meal_veto', 'meal_replacement', 'plan_finalized'] as const
export type NotificationKind = (typeof notificationKinds)[number]

export interface NotificationPreferences {
  masterEnabled: boolean
  invitesEnabled: boolean
  weeklyPlanEnabled: boolean
  mealVetoEnabled: boolean
  mealReplacementEnabled: boolean
  planFinalizedEnabled: boolean
}

export interface PushMessage {
  platform: 'ios' | 'android'
  token: string
  title: string
  body: string
  route: string
  kind: NotificationKind
  count: number
}

export interface LoggedPush {
  platform: 'ios' | 'android'
  title: string
  body: string
  route: string
  kind: NotificationKind
  count: number
}

export interface PushSender {
  readonly name: string
  send(message: PushMessage): Promise<void>
}

export interface NotificationBatch {
  id: string
  accountId: string
  householdId: string
  kind: NotificationKind
  windowStart: string
  eventCount: number
  title: string
  body: string
  route: string
  mealId: string
  status: 'pending' | 'sent' | 'skipped'
}

export interface DeviceToken {
  id: string
  platform: 'ios' | 'android'
  disabled: boolean
}

export interface NotificationStore {
  preferences(accountId: string): Promise<NotificationPreferences>
  savePreferences(accountId: string, prefs: NotificationPreferences): Promise<void>
  registerToken(accountId: string, token: string, platform: 'ios' | 'android'): Promise<void>
  unregisterToken(accountId: string, token: string): Promise<void>
  listTokens(accountId: string): Promise<DeviceToken[]>
  activeTokens(accountId: string): Promise<{ token: string; platform: 'ios' | 'android' }[]>
  openBatch(accountId: string, householdId: string, kind: NotificationKind, now: Date): Promise<NotificationBatch | null>
  saveBatch(batch: NotificationBatch): Promise<void>
  dueBatches(now: Date): Promise<NotificationBatch[]>
  listBatches(accountId: string): Promise<NotificationBatch[]>
  revokeAllTokens(accountId: string): Promise<void>
}

export function defaultPreferences(): NotificationPreferences {
  return {
    masterEnabled: true,
    invitesEnabled: true,
    weeklyPlanEnabled: true,
    mealVetoEnabled: true,
    mealReplacementEnabled: true,
    planFinalizedEnabled: true,
  }
}

export function allows(prefs: NotificationPreferences, kind: NotificationKind): boolean {
  if (!prefs.masterEnabled) return false
  switch (kind) {
    case 'invite':
      return prefs.invitesEnabled
    case 'weekly_plan':
      return prefs.weeklyPlanEnabled
    case 'meal_veto':
      return prefs.mealVetoEnabled
    case 'meal_replacement':
      return prefs.mealReplacementEnabled
    case 'plan_finalized':
      return prefs.planFinalizedEnabled
  }
}

interface NotificationText {
  single: string
  grouped: (count: string) => string
}

/**
 * Push alert text by recipient locale. Only tr-TR ships; any other locale falls back to
 * `NOTIFICATION_FALLBACK_LOCALE`. Kinds, routes and grouping never depend on the text.
 */
export const NOTIFICATION_MESSAGES: Readonly<Record<string, Readonly<Record<NotificationKind, NotificationText>>>> = Object.freeze({
  'tr-TR': {
    invite: { single: 'Ev halkı daveti', grouped: (count) => `${count} ev halkı daveti` },
    weekly_plan: { single: 'Haftalık plan hazır', grouped: (count) => `${count} plan güncellemesi` },
    meal_veto: { single: 'Bir yemek için bu hafta olmaz', grouped: (count) => `${count} yemek için bu hafta olmaz` },
    meal_replacement: { single: 'Bir yemek değişti', grouped: (count) => `${count} yemek değişti` },
    plan_finalized: { single: 'Haftalık plan kesinleşti', grouped: (count) => `${count} plan kesinleşti` },
  },
})

export const NOTIFICATION_FALLBACK_LOCALE = 'tr-TR'

export function notificationCopy(
  kind: NotificationKind,
  count: number,
  mealId: string,
  inviteCode: string,
  locale: string = NOTIFICATION_FALLBACK_LOCALE,
): { title: string; body: string; route: string } {
  const grouped = count > 1
  const title = 'MealRoutine'
  const messageLocale = NOTIFICATION_MESSAGES[locale] ? locale : NOTIFICATION_FALLBACK_LOCALE
  const text = NOTIFICATION_MESSAGES[messageLocale]![kind]
  const body = grouped ? text.grouped(new Intl.NumberFormat(messageLocale).format(count)) : text.single
  switch (kind) {
    case 'invite':
      return {
        title,
        body,
        route: inviteCode ? `mealroutine://household/join?code=${inviteCode}` : 'mealroutine://household/join',
      }
    case 'weekly_plan':
    case 'plan_finalized':
      return { title, body, route: 'mealroutine://week' }
    case 'meal_veto':
    case 'meal_replacement':
      return { title, body, route: grouped || !mealId ? 'mealroutine://week' : `mealroutine://week/meal?id=${mealId}` }
  }
}

export function kindForMutation(input: {
  entityType: string
  entityId: string
  operationType: string
  baseRevision: number
  payload: Record<string, unknown>
}): { kind: NotificationKind; mealId: string } | null {
  if (input.entityType === 'reaction' && input.operationType === 'set' && input.payload.reaction === 'veto') {
    return { kind: 'meal_veto', mealId: safeMealId(String(input.entityId)) }
  }
  if (input.entityType === 'meal' && input.operationType === 'replace') {
    return { kind: 'meal_replacement', mealId: safeMealId(String(input.entityId)) }
  }
  if (input.entityType === 'plan' && input.operationType === 'upsert') {
    if (input.payload.isFinalized === true) return { kind: 'plan_finalized', mealId: '' }
    if (input.baseRevision === 0) return { kind: 'weekly_plan', mealId: '' }
  }
  return null
}

export function createLogSender(): PushSender & { messages: LoggedPush[] } {
  const messages: LoggedPush[] = []
  return {
    name: 'log',
    messages,
    async send(message) {
      messages.push({
        platform: message.platform,
        title: message.title,
        body: message.body,
        route: message.route,
        kind: message.kind,
        count: message.count,
      })
    },
  }
}

export interface FcmSender extends PushSender {
  readonly configured: boolean
}

export function createFcmSender(serverKey: string | undefined): FcmSender {
  return {
    name: 'fcm',
    configured: Boolean(serverKey?.trim()),
    async send() {
      // Placeholder for a future Android or Flutter client. No FCM request is made.
    },
  }
}

export interface ApnsConfig {
  keyId: string
  teamId: string
  bundleId: string
  privateKey: string
  production: boolean
}

export function apnsConfigFromEnv(env: NodeJS.ProcessEnv = process.env): ApnsConfig | null {
  const keyId = env.APNS_KEY_ID?.trim() ?? ''
  const teamId = env.APNS_TEAM_ID?.trim() ?? ''
  const bundleId = env.APNS_BUNDLE_ID?.trim() ?? ''
  const inline = env.APNS_KEY_P8?.trim() ?? ''
  const path = env.APNS_KEY_PATH?.trim() ?? ''
  if (!keyId || !teamId || !bundleId || (!inline && !path)) return null
  const privateKey = inline || readFileSync(path, 'utf8')
  return { keyId, teamId, bundleId, privateKey, production: env.APNS_PRODUCTION === 'true' }
}

export function createApnsSender(config: ApnsConfig): PushSender {
  return {
    name: 'apns',
    async send(message) {
      if (message.platform !== 'ios' || !message.token) return
      const jwt = apnsJwt(config)
      const origin = config.production ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com'
      const client = http2.connect(origin)
      try {
        await new Promise<void>((resolve, reject) => {
          client.on('error', reject)
          const req = client.request({
            ':method': 'POST',
            ':path': `/3/device/${message.token}`,
            authorization: `bearer ${jwt}`,
            'apns-topic': config.bundleId,
            'apns-push-type': 'alert',
          })
          req.on('error', reject)
          req.on('response', (headers) => {
            const status = Number(headers[':status'] ?? 0)
            if (status >= 200 && status < 300) resolve()
            else reject(new Error('apns_rejected'))
          })
          req.end(JSON.stringify({
            aps: { alert: { title: message.title, body: message.body } },
            route: message.route,
            kind: message.kind,
            count: message.count,
          }))
        })
      } finally {
        client.close()
      }
    },
  }
}

export function createPushSender(env: NodeJS.ProcessEnv = process.env): PushSender {
  const apnsConfig = apnsConfigFromEnv(env)
  const apns = apnsConfig ? createApnsSender(apnsConfig) : null
  const log = createLogSender()
  const fcm = createFcmSender(env.FCM_SERVER_KEY)
  return {
    name: apns ? 'apns' : 'log',
    async send(message) {
      if (message.platform === 'android') {
        await fcm.send(message)
        await log.send(message)
        return
      }
      if (apns) await apns.send(message)
      else await log.send(message)
    },
  }
}

export function createNotificationService(store: NotificationStore, sender: PushSender, now: () => Date = () => new Date()) {
  return {
    preferences(accountId: string) {
      return store.preferences(accountId)
    },
    savePreferences(accountId: string, prefs: NotificationPreferences) {
      return store.savePreferences(accountId, prefs)
    },
    registerToken(accountId: string, token: string, platform: 'ios' | 'android') {
      return store.registerToken(accountId, token, platform)
    },
    unregisterToken(accountId: string, token: string) {
      return store.unregisterToken(accountId, token)
    },
    listTokens(accountId: string) {
      return store.listTokens(accountId)
    },
    async enqueue(
      accountId: string,
      householdId: string,
      kind: NotificationKind,
      mealId: string,
      inviteCode: string,
      locale: string = NOTIFICATION_FALLBACK_LOCALE,
    ): Promise<NotificationBatch | null> {
      const prefs = await store.preferences(accountId)
      if (!allows(prefs, kind)) return null
      const clock = now()
      const safeMeal = safeMealId(mealId)
      const safeInvite = safeCode(inviteCode)
      const open = await store.openBatch(accountId, householdId, kind, clock)
      const count = (open?.eventCount ?? 0) + 1
      const copy = notificationCopy(kind, count, safeMeal, safeInvite, locale)
      const batch: NotificationBatch = open
        ? { ...open, eventCount: count, title: copy.title, body: copy.body, route: copy.route, mealId: safeMeal, status: 'pending' }
        : {
            id: randomUUID(),
            accountId,
            householdId,
            kind,
            windowStart: clock.toISOString(),
            eventCount: 1,
            title: copy.title,
            body: copy.body,
            route: copy.route,
            mealId: safeMeal,
            status: 'pending',
          }
      await store.saveBatch(batch)
      await this.dispatch()
      return batch
    },
    async dispatch(): Promise<number> {
      const due = await store.dueBatches(now())
      let sent = 0
      for (const batch of due) {
        const tokens = await store.activeTokens(batch.accountId)
        for (const device of tokens) {
          await sender.send({
            platform: device.platform,
            token: device.token,
            title: batch.title,
            body: batch.body,
            route: batch.route,
            kind: batch.kind,
            count: batch.eventCount,
          })
        }
        await store.saveBatch({ ...batch, status: 'sent' })
        sent += 1
      }
      return sent
    },
    listBatches(accountId: string) {
      return store.listBatches(accountId)
    },
  }
}

export function createMemoryNotificationStore(): NotificationStore {
  const prefs = new Map<string, NotificationPreferences>()
  const tokens = new Map<string, { id: string; accountId: string; token: string; hash: string; platform: 'ios' | 'android'; disabled: boolean }>()
  const batches = new Map<string, NotificationBatch>()

  return {
    async preferences(accountId) {
      return prefs.get(accountId) ?? defaultPreferences()
    },
    async savePreferences(accountId, next) {
      prefs.set(accountId, next)
    },
    async registerToken(accountId, token, platform) {
      const hash = tokenHash(token)
      const key = `${accountId}:${hash}`
      const existing = tokens.get(key)
      tokens.set(key, { id: existing?.id ?? randomUUID(), accountId, token, hash, platform, disabled: false })
    },
    async unregisterToken(accountId, token) {
      tokens.delete(`${accountId}:${tokenHash(token)}`)
    },
    async listTokens(accountId) {
      return [...tokens.values()]
        .filter((row) => row.accountId === accountId)
        .map((row) => ({ id: row.id, platform: row.platform, disabled: row.disabled }))
    },
    async activeTokens(accountId) {
      return [...tokens.values()]
        .filter((row) => row.accountId === accountId && !row.disabled)
        .map((row) => ({ token: row.token, platform: row.platform }))
    },
    async openBatch(accountId, householdId, kind, clock) {
      return [...batches.values()].find((batch) =>
        batch.accountId === accountId
        && batch.householdId === householdId
        && batch.kind === kind
        && batch.status === 'pending'
        && clock.getTime() - Date.parse(batch.windowStart) < GROUP_WINDOW_MS
      ) ?? null
    },
    async saveBatch(batch) {
      batches.set(batch.id, batch)
    },
    async dueBatches(clock) {
      return [...batches.values()].filter((batch) =>
        batch.status === 'pending' && clock.getTime() - Date.parse(batch.windowStart) >= GROUP_WINDOW_MS
      )
    },
    async listBatches(accountId) {
      return [...batches.values()].filter((batch) => batch.accountId === accountId)
    },
    async revokeAllTokens(accountId) {
      for (const [key, row] of tokens) {
        if (row.accountId === accountId) tokens.set(key, { ...row, disabled: true })
      }
      prefs.delete(accountId)
      for (const [id, batch] of batches) {
        if (batch.accountId === accountId) batches.delete(id)
      }
    },
  }
}

export function createPgNotificationStore(pool: Pool): NotificationStore {
  return {
    async preferences(accountId) {
      const result = await pool.query(
        `SELECT master_enabled, invites_enabled, weekly_plan_enabled, meal_veto_enabled, meal_replacement_enabled, plan_finalized_enabled
           FROM notification_preferences WHERE account_id = $1`,
        [accountId],
      )
      const row = result.rows[0]
      if (!row) return defaultPreferences()
      return {
        masterEnabled: Boolean(row.master_enabled),
        invitesEnabled: Boolean(row.invites_enabled),
        weeklyPlanEnabled: Boolean(row.weekly_plan_enabled),
        mealVetoEnabled: Boolean(row.meal_veto_enabled),
        mealReplacementEnabled: Boolean(row.meal_replacement_enabled),
        planFinalizedEnabled: Boolean(row.plan_finalized_enabled),
      }
    },
    async savePreferences(accountId, prefs) {
      await pool.query(
        `INSERT INTO notification_preferences (
           account_id, master_enabled, invites_enabled, weekly_plan_enabled, meal_veto_enabled, meal_replacement_enabled, plan_finalized_enabled, updated_at
         ) VALUES ($1,$2,$3,$4,$5,$6,$7, now())
         ON CONFLICT (account_id) DO UPDATE SET
           master_enabled = EXCLUDED.master_enabled,
           invites_enabled = EXCLUDED.invites_enabled,
           weekly_plan_enabled = EXCLUDED.weekly_plan_enabled,
           meal_veto_enabled = EXCLUDED.meal_veto_enabled,
           meal_replacement_enabled = EXCLUDED.meal_replacement_enabled,
           plan_finalized_enabled = EXCLUDED.plan_finalized_enabled,
           updated_at = now()`,
        [accountId, prefs.masterEnabled, prefs.invitesEnabled, prefs.weeklyPlanEnabled, prefs.mealVetoEnabled, prefs.mealReplacementEnabled, prefs.planFinalizedEnabled],
      )
    },
    async registerToken(accountId, token, platform) {
      const hash = tokenHash(token)
      await pool.query(
        `INSERT INTO device_push_tokens (id, account_id, token, token_hash, platform, disabled_at)
         VALUES ($1,$2,$3,$4,$5, NULL)
         ON CONFLICT (account_id, token_hash) DO UPDATE SET token = EXCLUDED.token, platform = EXCLUDED.platform, disabled_at = NULL`,
        [randomUUID(), accountId, token, hash, platform],
      )
    },
    async unregisterToken(accountId, token) {
      await pool.query(
        `UPDATE device_push_tokens SET disabled_at = now() WHERE account_id = $1 AND token_hash = $2`,
        [accountId, tokenHash(token)],
      )
    },
    async listTokens(accountId) {
      const result = await pool.query<{ id: string; platform: 'ios' | 'android'; disabled_at: Date | null }>(
        `SELECT id::text, platform, disabled_at FROM device_push_tokens WHERE account_id = $1`,
        [accountId],
      )
      return result.rows.map((row) => ({ id: row.id, platform: row.platform, disabled: row.disabled_at != null }))
    },
    async activeTokens(accountId) {
      const result = await pool.query<{ token: string; platform: 'ios' | 'android' }>(
        `SELECT token, platform FROM device_push_tokens WHERE account_id = $1 AND disabled_at IS NULL`,
        [accountId],
      )
      return result.rows
    },
    async openBatch(accountId, householdId, kind, clock) {
      const result = await pool.query(
        `SELECT id::text, account_id::text, household_id::text, kind, window_start, event_count, title, body, route, meal_id, status
           FROM notification_batches
          WHERE account_id = $1 AND household_id = $2 AND kind = $3 AND status = 'pending'
            AND window_start > $4
          ORDER BY window_start DESC
          LIMIT 1`,
        [accountId, householdId, kind, new Date(clock.getTime() - GROUP_WINDOW_MS)],
      )
      return result.rows[0] ? batchFrom(result.rows[0]) : null
    },
    async saveBatch(batch) {
      await pool.query(
        `INSERT INTO notification_batches (
           id, account_id, household_id, kind, window_start, event_count, last_event_at, title, body, route, meal_id, status, sent_at
         ) VALUES ($1,$2,$3,$4,$5,$6, now(), $7,$8,$9,$10,$11, CASE WHEN $11 = 'sent' THEN now() ELSE NULL END)
         ON CONFLICT (id) DO UPDATE SET
           event_count = EXCLUDED.event_count,
           last_event_at = now(),
           title = EXCLUDED.title,
           body = EXCLUDED.body,
           route = EXCLUDED.route,
           meal_id = EXCLUDED.meal_id,
           status = EXCLUDED.status,
           sent_at = CASE WHEN EXCLUDED.status = 'sent' THEN now() ELSE notification_batches.sent_at END`,
        [batch.id, batch.accountId, batch.householdId, batch.kind, batch.windowStart, batch.eventCount, batch.title, batch.body, batch.route, batch.mealId, batch.status],
      )
    },
    async dueBatches(clock) {
      const result = await pool.query(
        `SELECT id::text, account_id::text, household_id::text, kind, window_start, event_count, title, body, route, meal_id, status
           FROM notification_batches
          WHERE status = 'pending' AND window_start <= $1`,
        [new Date(clock.getTime() - GROUP_WINDOW_MS)],
      )
      return result.rows.map(batchFrom)
    },
    async revokeAllTokens(accountId) {
      await pool.query(
        `UPDATE device_push_tokens SET disabled_at = now() WHERE account_id = $1 AND disabled_at IS NULL`,
        [accountId],
      )
      await pool.query(`DELETE FROM notification_preferences WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM notification_batches WHERE account_id = $1`, [accountId])
    },
    async listBatches(accountId) {
      const result = await pool.query(
        `SELECT id::text, account_id::text, household_id::text, kind, window_start, event_count, title, body, route, meal_id, status
           FROM notification_batches WHERE account_id = $1`,
        [accountId],
      )
      return result.rows.map(batchFrom)
    },
  }
}

function batchFrom(row: Record<string, unknown>): NotificationBatch {
  return {
    id: String(row.id),
    accountId: String(row.account_id),
    householdId: String(row.household_id),
    kind: String(row.kind) as NotificationKind,
    windowStart: new Date(String(row.window_start)).toISOString(),
    eventCount: Number(row.event_count),
    title: String(row.title ?? ''),
    body: String(row.body ?? ''),
    route: String(row.route ?? ''),
    mealId: String(row.meal_id ?? ''),
    status: (row.status === 'sent' || row.status === 'skipped' ? row.status : 'pending') as NotificationBatch['status'],
  }
}

function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

function safeMealId(raw: string): string {
  return raw.replace(/[^a-zA-Z0-9-]/g, '').slice(0, 80)
}

function safeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^ABCDEFGHJKLMNPQRSTUVWXYZ23456789]/g, '').slice(0, 6)
}

function apnsJwt(config: ApnsConfig): string {
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.keyId }))
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: Math.floor(Date.now() / 1000) }))
  const unsigned = `${header}.${claims}`
  const signer = createSign('SHA256')
  signer.update(unsigned)
  const signature = signer.sign({ key: config.privateKey, dsaEncoding: 'ieee-p1363' })
  return `${unsigned}.${base64url(signature)}`
}

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString('base64url')
}
