const { test, expect } = require('@playwright/test');

async function addFirstProductToCart(page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('a[href*="/product"]').first().click();

  const addToCartButton = page.getByRole('button', { name: /add/i });
  await expect(addToCartButton).toBeVisible();
  await addToCartButton.click();

  await expect(page).toHaveURL(/\/cart/);
}

async function fillCheckoutForm(page) {
  await page.getByLabel(/E-mail Address/i).fill('massi@quantikmind.com');
  await page.getByLabel(/Street Address/i).fill('Quantum Street 42');
  await page.getByLabel(/Zip Code/i).fill('8000');
  await page.getByLabel(/City/i).fill('Zurich');
  await page.getByLabel(/State/i).fill('ZH');
  await page.getByLabel(/Country/i).fill('Switzerland');

  await page.getByLabel(/Credit Card Number/i).fill('4111111111111111');
  await page.getByLabel(/CVV/i).fill('123');
}

test('order-complete-happy-path', async ({ page }) => {
  await addFirstProductToCart(page);
  await fillCheckoutForm(page);

  await page.getByRole('button', { name: /Place Order/i }).click();

  await expect(page.locator('body')).toContainText(/order|complete|thank you/i);
});

test('order-form-requires-payment-data', async ({ page }) => {
  await addFirstProductToCart(page);

  await page.getByRole('button', { name: /Place Order/i }).click();

  await expect(page.locator('body')).not.toContainText(/order complete|thank you/i);
});

