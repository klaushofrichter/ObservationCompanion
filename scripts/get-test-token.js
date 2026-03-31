#!/usr/bin/env node
/**
 * Token Acquisition Script for Swift Integration Tests
 *
 * Uses Playwright to automate EEN OAuth login and obtain auth credentials,
 * then writes them to test-credentials.json for Swift tests to consume.
 *
 * Usage:
 *   node scripts/get-test-token.js
 *   PROXY_URL=https://my-proxy.workers.dev node scripts/get-test-token.js
 *
 * Requires TEST_USER and TEST_PASSWORD in .env (project root) or as environment variables.
 * Optionally set CLIENT_ID and PROXY_URL.
 */

import { chromium } from 'playwright'
import { config } from 'dotenv'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import { writeFileSync } from 'fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT_DIR = resolve(__dirname, '..')

// Load environment from .env in project root
config({ path: resolve(ROOT_DIR, '.env') })

const PROXY_URL = process.env.PROXY_URL || 'http://127.0.0.1:3333'
const CLIENT_ID = process.env.CLIENT_ID || 'PREVIEW-KLAUS-MOBILE'
const TEST_USER = process.env.TEST_USER
const TEST_PASSWORD = process.env.TEST_PASSWORD
const OUTPUT_FILE = resolve(ROOT_DIR, 'test-credentials.json')

if (!TEST_USER || !TEST_PASSWORD) {
  console.error('Error: TEST_USER and TEST_PASSWORD must be set in .env or as environment variables')
  process.exit(1)
}

/**
 * Automate EEN OAuth login to get an authorization code.
 */
async function getAuthCode() {
  const redirectUri = PROXY_URL
  const state = crypto.randomUUID()
  const authorizeUrl = `https://auth.eagleeyenetworks.com/oauth2/authorize?` +
    `client_id=${encodeURIComponent(CLIENT_ID)}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}` +
    `&response_type=code&scope=vms.all&state=${state}`

  const browser = await chromium.launch({ headless: true })
  const context = await browser.newContext()
  const page = await context.newPage()

  try {
    await page.goto(authorizeUrl, { waitUntil: 'networkidle', timeout: 30000 })
    await page.waitForTimeout(2000)

    // Fill email
    const emailSelectors = ['#authentication--input__email', 'input[type="email"]', 'input[placeholder*="email" i]']
    let emailInput = null
    for (const sel of emailSelectors) {
      const el = page.locator(sel)
      if (await el.isVisible().catch(() => false)) {
        emailInput = el
        break
      }
    }
    if (!emailInput) {
      await page.locator('#authentication--input__email').waitFor({ state: 'visible', timeout: 30000 })
      emailInput = page.locator('#authentication--input__email')
    }

    await emailInput.fill(TEST_USER)
    await page.getByRole('button', { name: 'Next' }).click()

    // Fill password
    const passwordInput = page.locator('#authentication--input__password')
    await passwordInput.waitFor({ state: 'visible', timeout: 10000 })
    await passwordInput.fill(TEST_PASSWORD)

    // Click sign in
    try {
      await page.locator('#next').click()
    } catch {
      await page.getByRole('button', { name: 'Sign in' }).click()
    }

    // Wait for redirect with ?code=
    await page.waitForURL(url => {
      const u = new URL(url)
      return u.origin === new URL(PROXY_URL).origin && u.searchParams.has('code')
    }, { timeout: 30000 })

    const redirectedUrl = new URL(page.url())
    const code = redirectedUrl.searchParams.get('code')
    if (!code) throw new Error('No authorization code in redirect URL')
    return code
  } finally {
    await browser.close()
  }
}

/**
 * Exchange authorization code for session token via the proxy.
 */
async function exchangeCode(code) {
  const res = await fetch(`${PROXY_URL}/proxy/getAccessToken`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ code, redirect_uri: PROXY_URL }).toString()
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Token exchange failed (${res.status}): ${text}`)
  }
  return res.json()
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Getting test credentials via ${PROXY_URL}...`)
  console.log(`User: ${TEST_USER}`)

  const code = await getAuthCode()
  console.log('Got authorization code, exchanging for token...')

  const tokenData = await exchangeCode(code)
  console.log(`Got access token for ${tokenData.userEmail || 'unknown'}`)

  // httpsBaseUrl may be a string or an object like { hostname, port }
  let baseUrl = tokenData.httpsBaseUrl
  if (typeof baseUrl === 'object' && baseUrl !== null && baseUrl.hostname) {
    const port = baseUrl.port && baseUrl.port !== 443 ? `:${baseUrl.port}` : ''
    baseUrl = `https://${baseUrl.hostname}${port}`
  }

  const credentials = {
    accessToken: tokenData.accessToken,
    sessionId: tokenData.sessionId,
    httpsBaseUrl: baseUrl,
    userEmail: tokenData.userEmail,
    expiresIn: tokenData.expiresIn
  }

  writeFileSync(OUTPUT_FILE, JSON.stringify(credentials, null, 2))
  console.log(`Credentials written to ${OUTPUT_FILE}`)
}

main().catch(err => {
  console.error(`Fatal error: ${err.message}`)
  process.exit(1)
})
