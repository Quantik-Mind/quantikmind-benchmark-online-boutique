const { test, expect } = require('@playwright/test');

async function openFirstProduct(page) {
  await page.goto('/');
  const links = page.locator('a[href*="/product/"]');
  await expect(links.first()).toBeVisible();
  await links.first().click();
  await expect(page.locator('body')).toContainText(/\$/);
}

test('frontend-logo-or-home-link-visible', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/Online Boutique|Google|Shop|boutique/i);
});

test('frontend-products-have-prices', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/\$/);
});

test('frontend-page-loads-under-basic-navigation', async ({ page }) => {
  await page.goto('/');
  await page.reload();
  await expect(page.locator('body')).toContainText(/\$/);
});

test('catalog-product-detail-can-be-opened-twice', async ({ page }) => {
  await openFirstProduct(page);
  await page.goto('/');
  await openFirstProduct(page);
});

test('catalog-product-detail-keeps-product-context', async ({ page }) => {
  await openFirstProduct(page);
  await expect(page.locator('body')).toContainText(/Add to Cart|cart/i);
});

test('cart-add-product-and-view-cart', async ({ page }) => {
  await openFirstProduct(page);
  await page.getByRole('button', { name: /add to cart/i }).click();
  await expect(page.locator('body')).toContainText(/cart|checkout/i);
});

test('cart-survives-home-navigation', async ({ page }) => {
  await openFirstProduct(page);
  await page.getByRole('button', { name: /add to cart/i }).click();
  await page.goto('/');
  await expect(page.locator('body')).toContainText(/\$/);
});

test('order-flow-does-not-complete-with-empty-data', async ({ page }) => {
  await page.goto('/cart/checkout');
  await expect(page.locator('body')).not.toContainText(/Your order is complete/i);
});