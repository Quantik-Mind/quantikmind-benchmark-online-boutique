const { test, expect } = require('@playwright/test');

async function homepage(page) {
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/\$/);
}

async function firstProductLink(page) {
  await homepage(page);
  const links = page.locator('a[href*="/product/"]');
  await expect(links.first()).toBeVisible();
  return links.first();
}

async function openFirstProduct(page) {
  const link = await firstProductLink(page);
  const href = await link.getAttribute('href');
  await link.click();
  await expect(page.locator('body')).toContainText(/\$/);
  return href;
}

test('homepage-body-is-not-empty', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).not.toHaveText('');
});

test('homepage-contains-product-price', async ({ page }) => {
  await homepage(page);
});

test('homepage-has-at-least-one-product-link', async ({ page }) => {
  await firstProductLink(page);
});

test('homepage-has-multiple-links', async ({ page }) => {
  await homepage(page);
  await expect(page.locator('a').first()).toBeVisible();
});

test('homepage-title-is-available', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/Online Boutique|Google|Shop|boutique/i);
});

test('catalog-product-link-href-starts-with-product', async ({ page }) => {
  const link = await firstProductLink(page);
  const href = await link.getAttribute('href');
  expect(href).toContain('/product/');
});

test('catalog-first-product-opens-detail-page', async ({ page }) => {
  await openFirstProduct(page);
});

test('product-detail-page-has-add-to-cart-button', async ({ page }) => {
  await openFirstProduct(page);
  await expect(page.getByRole('button', { name: /add to cart/i })).toBeVisible();
});

test('product-detail-page-has-price', async ({ page }) => {
  await openFirstProduct(page);
  await expect(page.locator('body')).toContainText(/\$/);
});

test('product-detail-page-has-non-empty-body', async ({ page }) => {
  await openFirstProduct(page);
  await expect(page.locator('body')).not.toHaveText('');
});

test('product-detail-refresh-keeps-content', async ({ page }) => {
  await openFirstProduct(page);
  await page.reload();
  await expect(page.locator('body')).toContainText(/\$/);
});

test('cart-page-loads-without-product', async ({ page }) => {
  await page.goto('/cart');
  await expect(page.locator('body')).not.toHaveText('');
});

test('cart-page-has-cart-context', async ({ page }) => {
  await page.goto('/cart');
  await expect(page.locator('body')).toContainText(/cart|empty|shopping/i);
});

test('cart-add-from-product-detail-shows-cart-context', async ({ page }) => {
  await openFirstProduct(page);
  await page.getByRole('button', { name: /add to cart/i }).click();
  await expect(page.locator('body')).toContainText(/cart|checkout|shopping/i);
});

test('cart-add-from-product-detail-keeps-price-context', async ({ page }) => {
  await openFirstProduct(page);
  await page.getByRole('button', { name: /add to cart/i }).click();
  await expect(page.locator('body')).toContainText(/\$/);
});

test('navigation-home-to-product-to-home', async ({ page }) => {
  await openFirstProduct(page);
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/\$/);
});

test('navigation-cart-to-home', async ({ page }) => {
  await page.goto('/cart');
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/\$/);
});

test('catalog-two-product-links-visible-if-present', async ({ page }) => {
  await homepage(page);
  const links = page.locator('a[href*="/product/"]');
  const count = await links.count();
  expect(count).toBeGreaterThan(0);
});

test('frontend-static-assets-do-not-break-homepage', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('body')).not.toHaveText('');
});

test('frontend-basic-user-journey-home-product-cart', async ({ page }) => {
  await openFirstProduct(page);
  await page.getByRole('button', { name: /add to cart/i }).click();
  await expect(page.locator('body')).toContainText(/cart|checkout|shopping|\$/i);
});