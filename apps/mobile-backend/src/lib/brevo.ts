import { env } from "../config/env.js"

export async function sendEmail({ to, subject, html }: { to: string; subject: string; html: string }) {
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "api-key": env.brevoApiKey,
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body: JSON.stringify({
      sender: { email: env.brevoSenderEmail, name: env.brevoSenderName },
      to: [{ email: to }],
      subject,
      htmlContent: html,
    }),
  })

  if (!res.ok) {
    const body = await res.text().catch(() => "")
    throw new Error(`Brevo send failed (${res.status}): ${body}`)
  }
}

export function resetCodeEmailHtml(code: string): string {
  return `
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
      <p>Your password reset code for AapliSocietyy is:</p>
      <p style="font-size: 32px; font-weight: 700; letter-spacing: 4px;">${code}</p>
      <p>This code expires in 10 minutes. If you didn't request this, you can ignore this email.</p>
    </div>
  `
}
