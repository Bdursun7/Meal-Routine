import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { ownedRecipeID } from '../src/migrationService.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

const recipeId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const otherId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const lineId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const historyId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'

describe('personal migration', () => {
  it('merges by newest field group, stays idempotent, and ignores a client owner', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'ada-migration')
    const first = await upload(app, ada.token, payload({
      nameTr: 'Menemen',
      updatedAt: '2024-02-01T00:00:00Z',
      ingredients: [line('Yumurta')],
      ownerAccountId: '00000000-0000-4000-8000-000000000099',
    }))
    expect(first.statusCode).toBe(200)
    expect(first.json().counts.recipes).toBe(1)
    expect(first.json().counts.history).toBe(1)
    expect(first.json().counts.favorites).toBe(1)

    const older = await upload(app, ada.token, payload({
      nameTr: 'Eski',
      updatedAt: '2024-01-01T00:00:00Z',
      ingredients: [line('Süt')],
    }))
    expect(older.statusCode).toBe(200)
    expect(older.json().counts.recipes).toBe(1)
    expect(older.json().counts.history).toBe(1)

    const newer = await upload(app, ada.token, payload({
      nameTr: 'Yeni menemen',
      updatedAt: '2024-06-01T00:00:00Z',
      ingredients: [],
      timesCooked: 1,
      neverAgain: true,
    }))
    expect(newer.statusCode).toBe(200)
    expect(newer.json().counts).toEqual(first.json().counts)

    const confirmed = await app.inject({
      method: 'POST',
      url: '/v1/migration/confirm',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(confirmed.statusCode).toBe(200)
    expect(confirmed.json().status).toBe('confirmed')

    const replay = await upload(app, ada.token, payload({
      nameTr: 'Yeni menemen',
      updatedAt: '2024-06-01T00:00:00Z',
      ingredients: [],
      timesCooked: 1,
      neverAgain: true,
    }))
    expect(replay.json().status).toBe('confirmed')
    expect(replay.json().counts.history).toBe(1)
    expect(replay.json().counts.recipes).toBe(1)

    const status = await app.inject({
      method: 'GET',
      url: '/v1/migration',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(status.json().counts.memories).toBe(1)
    expect(status.json().status).toBe('confirmed')
    await app.close()
  })

  it('keeps the newer name and the older ingredients when a newer list is empty', async () => {
    const { mergeRecipe } = await import('../src/migrationRules.js')
    const server = recipe('Menemen', '2024-02-01T00:00:00Z', [line('Yumurta')])
    const incoming = recipe('Yeni menemen', '2024-06-01T00:00:00Z', [])
    const merged = mergeRecipe(server, incoming)
    expect(merged.nameTr).toBe('Yeni menemen')
    expect(merged.ingredients.map((item) => item.nameTr)).toEqual(['Yumurta'])
    expect(merged.id).toBe(server.id)

    const { mergeMemory } = await import('../src/migrationRules.js')
    const memory = mergeMemory(
      {
        recipeSlug: 'menemen',
        updatedAt: '2024-02-01T00:00:00Z',
        timesCooked: 4,
        timesReplaced: 1,
        timesSkipped: 0,
        lastCookedAt: '2024-01-01T00:00:00Z',
        lastSelectedAt: null,
        lovedCount: 2,
        okayCount: 0,
        latestRating: 'loved',
        neverAgain: false,
        timeConcernCount: 0,
        difficultyConcernCount: 0,
        portionConcernCount: 0,
        missingIngredientCount: 0,
        tooManyIngredientCount: 0,
        wouldMakeAgainCount: 0,
        isFavorite: true,
        discoveryStatus: 'known',
        confidence: 'high',
      },
      {
        recipeSlug: 'menemen',
        updatedAt: '2024-06-01T00:00:00Z',
        timesCooked: 1,
        timesReplaced: 0,
        timesSkipped: 0,
        lastCookedAt: null,
        lastSelectedAt: null,
        lovedCount: 0,
        okayCount: 0,
        latestRating: '',
        neverAgain: true,
        timeConcernCount: 0,
        difficultyConcernCount: 0,
        portionConcernCount: 0,
        missingIngredientCount: 0,
        tooManyIngredientCount: 0,
        wouldMakeAgainCount: 0,
        isFavorite: false,
        discoveryStatus: 'unknown',
        confidence: 'low',
      },
    )
    expect(memory.timesCooked).toBe(4)
    expect(memory.neverAgain).toBe(true)
    expect(memory.isFavorite).toBe(true)
    expect(memory.latestRating).toBe('loved')
    expect(memory.lastCookedAt).toBe('2024-01-01T00:00:00Z')
  })

  it('does not let another account read, duplicate, or claim history ids', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'ada-owner')
    const berk = await signIn(app, 'berk-other', 'berk@example.com')
    const saved = await upload(app, ada.token, payload({
      nameTr: 'Menemen',
      updatedAt: '2024-02-01T00:00:00Z',
      ingredients: [line('Yumurta')],
    }))
    expect(saved.statusCode).toBe(200)

    const hidden = await app.inject({
      method: 'GET',
      url: '/v1/migration',
      headers: { authorization: `Bearer ${berk.token}` },
    })
    expect(hidden.statusCode).toBe(200)
    expect(hidden.json()).toEqual({
      status: 'not_started',
      counts: { recipes: 0, memories: 0, favorites: 0, history: 0, feedback: 0 },
    })

    const stolen = await upload(app, berk.token, payload({
      nameTr: 'Çalıntı',
      updatedAt: '2024-07-01T00:00:00Z',
      ingredients: [],
    }))
    expect(stolen.statusCode).toBe(200)
    expect(stolen.json().counts.history).toBe(0)
    expect(stolen.json().counts.recipes).toBe(1)

    const adaAgain = await app.inject({
      method: 'GET',
      url: '/v1/migration',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(adaAgain.json().counts.history).toBe(1)
    expect(adaAgain.json().counts.recipes).toBe(1)
    expect(ownedRecipeID(ada.id, 'menemen')).not.toBe(ownedRecipeID(berk.id, 'menemen'))

    const anon = await app.inject({ method: 'POST', url: '/v1/migration/upload', payload: { recipes: [] } })
    expect(anon.statusCode).toBe(401)

    const builtin = await upload(app, ada.token, {
      ...payload({ nameTr: 'Katalog', updatedAt: '2024-08-01T00:00:00Z', ingredients: [] }),
      recipes: [{
        ...recipe('Katalog', '2024-08-01T00:00:00Z', []),
        id: otherId,
        slug: 'katalog',
        origin: 'builtIn',
      }],
    })
    expect(builtin.json().counts.recipes).toBe(1)
    await app.close()
  })
})

async function signIn(app: ReturnType<typeof buildApp>, subject: string, email?: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken: identityToken({
        subject,
        email: email ?? null,
        emailVerified: Boolean(email),
        givenName: subject,
      }),
      givenName: subject,
    },
  })
  expect(response.statusCode).toBe(200)
  return { token: response.json().accessToken as string, id: response.json().account.id as string }
}

async function upload(app: ReturnType<typeof buildApp>, token: string, body: Record<string, unknown>) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/migration/upload',
    headers: { authorization: `Bearer ${token}` },
    payload: body,
  })
  return response
}

function payload(options: {
  nameTr: string
  updatedAt: string
  ingredients: ReturnType<typeof line>[]
  ownerAccountId?: string
  timesCooked?: number
  neverAgain?: boolean
}) {
  return {
    ownerAccountId: options.ownerAccountId,
    preferences: {
      updatedAt: options.updatedAt,
      householdSize: 2,
      eveningsPerWeek: 5,
      maxCookMinutes: 45,
      dislikedIngredientIds: ['mushroom'],
      discoveryLevel: 'balanced',
      repeatPreference: 'balanced',
      difficultyPreference: 'openToHard',
      weekdayStyle: 'mostlyQuick',
      dismissedPatternIds: [],
      hasCompletedOnboarding: true,
    },
    recipes: [recipe(options.nameTr, options.updatedAt, options.ingredients)],
    memories: [{
      recipeSlug: 'menemen',
      updatedAt: options.updatedAt,
      timesCooked: options.timesCooked ?? 2,
      timesReplaced: 1,
      timesSkipped: 0,
      lastCookedAt: '2024-01-15T00:00:00Z',
      lastSelectedAt: null,
      lovedCount: 1,
      okayCount: 0,
      latestRating: 'loved',
      neverAgain: options.neverAgain ?? false,
      timeConcernCount: 0,
      difficultyConcernCount: 0,
      portionConcernCount: 0,
      missingIngredientCount: 0,
      tooManyIngredientCount: 0,
      wouldMakeAgainCount: 0,
      isFavorite: true,
      discoveryStatus: 'known',
      confidence: 'high',
    }],
    favorites: [{ recipeSlug: 'menemen', createdAt: options.updatedAt }],
    history: [{
      id: historyId,
      recipeSlug: 'menemen',
      eventType: 'cooked',
      planWeekId: null,
      plannedMealId: null,
      replacementReason: '',
      createdAt: options.updatedAt,
    }],
    feedback: [],
  }
}

function recipe(nameTr: string, updatedAt: string, ingredients: ReturnType<typeof line>[]) {
  return {
    id: recipeId,
    slug: 'menemen',
    updatedAt,
    nameTr,
    nameEn: 'Menemen',
    summaryTr: '',
    origin: 'manual',
    collectionState: 'savedToTry',
    sourceUrl: '',
    sourceKey: '',
    sourcePlatform: '',
    sourceTitle: '',
    userNotes: '',
    baseServings: 2,
    prepMinutes: 10,
    cookMinutes: 15,
    totalMinutes: 25,
    timeIsUnknown: false,
    servingsUnspecified: false,
    difficulty: 'easy',
    category: 'yumurta',
    country: 'TR',
    diets: [],
    tags: [],
    photoUrl: '',
    ingredients,
    steps: [],
  }
}

function line(nameTr: string) {
  return {
    id: lineId,
    sortIndex: 0,
    ingredientId: nameTr.toLowerCase(),
    nameTr,
    nameEn: nameTr,
    quantity: 2,
    unit: 'adet',
    noteTr: '',
    isOptional: false,
    includeInGrocery: true,
  }
}
