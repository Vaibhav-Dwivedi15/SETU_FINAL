"""
Email delivery via SMTP.

WHY EMAIL AND NOT SMS FOR OTP: SMS OTP in India needs a paid gateway
plus TRAI DLT sender-ID registration. This project has neither, and the
free SMS Gateway for Android setup already in use (see sms_service.py)
is a single phone with a single SIM -- fine for a handful of emergency
contact notifications, not appropriate as a login-critical dependency
that every new user hits. Email is free, has no telecom regulatory
dependency, and any Gmail account can send it via an App Password.

CONFIGURATION (all in .env, see app/core/config.py):
    SMTP_HOST=smtp.gmail.com
    SMTP_PORT=587
    SMTP_USERNAME=<your gmail address>
    SMTP_PASSWORD=<16-char Gmail App Password, NOT the account password>
    SMTP_FROM_EMAIL=<usually same as SMTP_USERNAME>
    SMTP_FROM_NAME=SETU

Gmail App Passwords require 2FA enabled on the account. The regular
account password will NOT work and Google will reject it.

FAILURE POSTURE -- IMPORTANT: send_email() returns a bool and never
raises. It returns False when SMTP is unconfigured or delivery fails,
and the caller MUST NOT report success to the user in that case (see
otp_service.py / routers/auth.py, which surface delivery failure
honestly rather than showing "code sent!" over a code that went
nowhere). Silently pretending an email was sent is exactly the kind of
demo-time lie this project's "shipped vs roadmap" rule exists to prevent.
"""
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger("setu.email")


def smtp_is_configured() -> bool:
    """
    True only when every field required for an actual send is present.
    Checked before attempting delivery so an unconfigured deployment
    produces a clear, actionable error instead of a confusing SMTP
    traceback.
    """
    return bool(
        settings.smtp_host
        and settings.smtp_port
        and settings.smtp_username
        and settings.smtp_password
        and settings.smtp_from_email
    )


def send_email(to_email: str, subject: str, body_text: str, body_html: str | None = None) -> bool:
    """
    Sends one email. Returns True only if the SMTP server accepted it.
    Never raises -- every failure path is logged and returned as False.
    """
    if not smtp_is_configured():
        logger.warning(
            "SMTP is not configured (need SMTP_HOST/PORT/USERNAME/PASSWORD/FROM_EMAIL "
            "in .env) -- cannot send email to %s", to_email
        )
        return False

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    message["To"] = to_email
    message.set_content(body_text)
    if body_html:
        message.add_alternative(body_html, subtype="html")

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
            smtp.starttls()
            smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(message)
        logger.info("Sent email to %s (subject: %s)", to_email, subject)
        return True
    except Exception:
        logger.exception("Failed to send email to %s", to_email)
        return False


def send_otp_email(to_email: str, code: str, expiry_minutes: int) -> bool:
    """
    Sends the verification code. The code appears in both the plain-text
    and HTML parts so it's readable in any client.
    """
    subject = f"{code} is your SETU verification code"

    body_text = (
        f"Your SETU verification code is: {code}\n\n"
        f"This code expires in {expiry_minutes} minutes.\n\n"
        "If you did not request this code, you can safely ignore this email. "
        "Nobody from SETU will ever ask you for it.\n\n"
        "-- SETU, offline-first emergency mesh communication"
    )

    body_html = f"""\
<html>
  <body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#f1f5f9;padding:32px;">
    <div style="max-width:440px;margin:0 auto;background:#ffffff;border-radius:12px;padding:28px;">
      <h2 style="margin:0 0 4px;color:#0f172a;">SETU</h2>
      <p style="margin:0 0 22px;color:#475569;font-size:14px;">Emergency mesh communication</p>
      <p style="margin:0 0 10px;color:#0f172a;font-size:15px;">Your verification code:</p>
      <p style="font-family:monospace;font-size:34px;font-weight:700;letter-spacing:7px;
                color:#0f172a;background:#f1f5f9;border-radius:8px;padding:16px;text-align:center;margin:0 0 18px;">
        {code}
      </p>
      <p style="margin:0 0 14px;color:#475569;font-size:14px;">
        This code expires in {expiry_minutes} minutes.
      </p>
      <p style="margin:0;color:#94a3b8;font-size:12px;line-height:1.6;">
        If you did not request this code, you can safely ignore this email.
        Nobody from SETU will ever ask you for it.
      </p>
    </div>
  </body>
</html>"""

    return send_email(to_email, subject, body_text, body_html)
