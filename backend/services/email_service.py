import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart


def send_reset_email(to_email: str, username: str, code: str) -> dict:
    """
    Send a 6-digit password reset code to the user via Gmail SMTP.

    This is completely free — it uses your own Gmail account as the sender.
    You must generate a Gmail App Password (NOT your normal Gmail password):
        1. Go to myaccount.google.com → Security → 2-Step Verification (must be ON)
        2. Then Security → App Passwords → Select app: Mail → Generate
        3. Copy the 16-character password shown

    Environment variables required:
        GMAIL_USER         – your Gmail address e.g. yourapp@gmail.com
        GMAIL_APP_PASSWORD – the 16-char App Password (no spaces needed)

    Returns:
        { "success": True }
        { "success": False, "error": "..." }
    """
    gmail_user     = os.environ.get("GMAIL_USER")
    gmail_password = os.environ.get("GMAIL_APP_PASSWORD")

    if not all([gmail_user, gmail_password]):
        return {
            "success": False,
            "error":   (
                "Email credentials not configured. "
                "Set GMAIL_USER and GMAIL_APP_PASSWORD environment variables."
            ),
        }

    subject = "Smart Finance Tracker — Password Reset Code"
    body    = (
        f"Hello {username},\n\n"
        f"We received a request to reset your Smart Finance Tracker password.\n\n"
        f"Your 6-digit reset code is:\n\n"
        f"        {code}\n\n"
        f"This code expires in 15 minutes.\n\n"
        f"If you did not request a password reset, you can safely ignore this email. "
        f"Your account remains secure.\n\n"
        f"— Smart Finance Tracker\n"
        f"JKUAT, Juja, Kenya"
    )

    msg            = MIMEMultipart()
    msg["From"]    = f"Smart Finance Tracker <{gmail_user}>"
    msg["To"]      = to_email
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(gmail_user, gmail_password)
            server.sendmail(gmail_user, to_email, msg.as_string())
        return {"success": True}

    except smtplib.SMTPAuthenticationError:
        return {
            "success": False,
            "error":   (
                "Gmail authentication failed. "
                "Make sure GMAIL_APP_PASSWORD is the App Password, "
                "not your normal Gmail login password."
            ),
        }
    except smtplib.SMTPRecipientsRefused:
        return {
            "success": False,
            "error":   f"Invalid recipient email address: {to_email}",
        }
    except Exception as e:
        return {"success": False, "error": str(e)}