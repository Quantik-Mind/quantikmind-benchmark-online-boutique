const { test, expect } = require('@playwright/test');

test('cart-add-product-from-detail-page', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await page.locator('a[href*="/product"]').first().click();

  const addToCartButton = page.getByRole('button', { name: /add/i });
  await expect(addToCartButton).toBeVisible();

  await addToCartButton.click();

  await expect(page.locator('body')).toContainText(/cart|shopping cart|checkout/i);
});

test('cart-page-is-accessible', async ({ page }) => {
  await page.goto('/cart', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('body')).toContainText(/cart|shopping cart/i);
});

