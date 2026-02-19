import os
from twilio.rest import Client
from twilio.base.exceptions import TwilioRestException


def send_whatsapp(to_phone: str, message: str) -> dict:
    """
    Send a WhatsApp message to the guardian via Twilio.

    Twilio WhatsApp requires the number to be in the format:
    whatsapp:+254XXXXXXXXX

    Environment variables required:
        TWILIO_ACCOUNT_SID
        TWILIO_AUTH_TOKEN
        TWILIO_WHATSAPP_FROM   e.g. whatsapp:+14155238886 (Twilio sandbox number)

    Returns:
        { "success": True,  "sid": "..." }         on success
        { "success": False, "error": "..." }        on failure
    """
    account_sid = os.environ.get("TWILIO_ACCOUNT_SID")
    auth_token  = os.environ.get("TWILIO_AUTH_TOKEN")
    from_number = os.environ.get("TWILIO_WHATSAPP_FROM")

    if not all([account_sid, auth_token, from_number]):
        return {
            "success": False,
            "error":   "Twilio credentials not configured. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM."
        }

    # Normalise the recipient number
    to_whatsapp = _format_whatsapp_number(to_phone)

    try:
        client  = Client(account_sid, auth_token)
        msg     = client.messages.create(
            from_ = from_number,
            to    = to_whatsapp,
            body  = message,
        )
        return {"success": True, "sid": msg.sid}

    except TwilioRestException as e:
        return {"success": False, "error": str(e)}


def send_sms(to_phone: str, message: str) -> dict:
    """
    Send a plain SMS to the guardian via Twilio.
    Fallback channel if WhatsApp is not available.

    Environment variables required:
        TWILIO_ACCOUNT_SID
        TWILIO_AUTH_TOKEN
        TWILIO_SMS_FROM   e.g. +12345678901 (Twilio phone number)

    Returns:
        { "success": True,  "sid": "..." }
        { "success": False, "error": "..." }
    """
    account_sid = os.environ.get("TWILIO_ACCOUNT_SID")
    auth_token  = os.environ.get("TWILIO_AUTH_TOKEN")
    from_number = os.environ.get("TWILIO_SMS_FROM")

    if not all([account_sid, auth_token, from_number]):
        return {
            "success": False,
            "error":   "Twilio SMS credentials not configured. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_SMS_FROM."
        }

    to_e164 = _format_e164(to_phone)

    try:
        client = Client(account_sid, auth_token)
        msg    = client.messages.create(
            from_ = from_number,
            to    = to_e164,
            body  = message,
        )
        return {"success": True, "sid": msg.sid}

    except TwilioRestException as e:
        return {"success": False, "error": str(e)}


def dispatch(to_phone: str, message: str) -> dict:
    """
    Primary dispatch function called by the route.
    Attempts WhatsApp first, falls back to SMS if WhatsApp fails.

    Returns the result dict from whichever channel succeeded or both failed.
    """
    result = send_whatsapp(to_phone, message)
    if result["success"]:
        return {**result, "channel": "whatsapp"}

    # WhatsApp failed — try SMS
    sms_result = send_sms(to_phone, message)
    if sms_result["success"]:
        return {**sms_result, "channel": "sms"}

    # Both failed
    return {
        "success":  False,
        "channel":  None,
        "error":    f"WhatsApp: {result.get('error')} | SMS: {sms_result.get('error')}"
    }


# ─── Private helpers ──────────────────────────────────────────────────────────

def _format_whatsapp_number(phone: str) -> str:
    """
    Ensure number is in whatsapp:+XXXXXXXXXXX format.
    Handles numbers entered with or without country code.
    Defaults to Kenya (+254) if no country code prefix detected.
    """
    phone = phone.strip().replace(" ", "").replace("-", "")

    if phone.startswith("whatsapp:"):
        return phone
    if phone.startswith("+"):
        return f"whatsapp:{phone}"
    if phone.startswith("0"):
        return f"whatsapp:+254{phone[1:]}"  # Kenyan local format 07XX → +2547XX
    return f"whatsapp:+{phone}"


def _format_e164(phone: str) -> str:
    """
    Ensure number is in E.164 format (+XXXXXXXXXXX).
    Defaults to Kenya (+254) if no country code detected.
    """
    phone = phone.strip().replace(" ", "").replace("-", "")

    if phone.startswith("+"):
        return phone
    if phone.startswith("0"):
        return f"+254{phone[1:]}"
    return f"+{phone}"