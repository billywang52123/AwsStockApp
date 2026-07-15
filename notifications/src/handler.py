"""AWS Lambda entry point for the StockMood personalized-push demo."""

from __future__ import annotations

import json
import logging
import os
from datetime import date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from botocore.exceptions import ClientError

from bedrock_content_service import BedrockContentService
from candidate_service import select_candidate
from database import NotificationRepository, database_connection
from deduplicator import DeliveryDeduplicator
from sns_publisher import SnsPublisher

logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())


def _as_bool(value: Any, *, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _resolve_demo_date(event: dict[str, Any]) -> date:
    if event.get("demo_date"):
        return date.fromisoformat(str(event["demo_date"]))

    demo_year = int(event.get("demo_year", os.getenv("DEMO_YEAR", "2025")))
    today = datetime.now(ZoneInfo("Asia/Taipei")).date()
    try:
        return today.replace(year=demo_year)
    except ValueError:
        # Define deterministic behavior for a real-world Feb 29 mapped to a
        # non-leap demo year.
        return date(demo_year, 2, 28)


def lambda_handler(event: dict[str, Any] | None, context: Any) -> dict[str, Any]:
    event = event or {}
    demo_date = _resolve_demo_date(event)
    target_user_id = str(event["user_id"]).strip() if event.get("user_id") else None
    all_users = _as_bool(event.get("all_users"), default=False)
    dry_run = _as_bool(
        event.get("dry_run"), default=_as_bool(os.getenv("PUSH_DRY_RUN"), default=True)
    )
    use_bedrock = _as_bool(event.get("use_bedrock"), default=True)
    force_resend = _as_bool(event.get("force_resend"), default=False)
    threshold = float(
        event.get("threshold_percent", os.getenv("SIGNAL_THRESHOLD_PERCENT", "2.0"))
    )
    if threshold < 0:
        raise ValueError("threshold_percent must be non-negative")

    request_id = getattr(context, "aws_request_id", "local")
    logger.info(
        "Starting personalized push request_id=%s demo_date=%s dry_run=%s target_user=%s all_users=%s",
        request_id,
        demo_date,
        dry_run,
        target_user_id,
        all_users,
    )

    content_service = BedrockContentService()
    publisher = SnsPublisher()
    deduplicator = DeliveryDeduplicator() if not dry_run else None
    results: list[dict[str, Any]] = []

    with database_connection() as connection:
        repository = NotificationRepository(connection)
        user_ids = repository.list_user_ids(
            target_user_id,
            all_users,
            require_active_device=not dry_run,
        )
        market_rows = repository.market_rows_for_date(demo_date.isoformat())
        if not market_rows:
            return {
                "status": "skipped",
                "reason": "no_market_data",
                "demo_date": demo_date.isoformat(),
                "user_count": len(user_ids),
            }

        for user_id in user_ids:
            candidate = select_candidate(
                user_id=user_id,
                demo_date=demo_date.isoformat(),
                holdings=repository.holdings_for_user(user_id),
                market_rows=market_rows,
                threshold_percent=threshold,
            )
            if candidate is None:
                results.append({"user_id": user_id, "status": "no_candidate"})
                continue

            devices = repository.active_devices_for_user(user_id)
            content = content_service.generate(candidate, enabled=use_bedrock)
            result: dict[str, Any] = {
                "user_id": user_id,
                "status": "dry_run" if dry_run else "processed",
                "candidate": candidate.as_dict(),
                "content": content.as_dict(),
                "device_count": len(devices),
                "deliveries": [],
            }

            if not dry_run:
                assert deduplicator is not None
                for device in devices:
                    dedupe_key = deduplicator.key(
                        demo_date=candidate.demo_date,
                        user_id=user_id,
                        symbol=candidate.symbol,
                        device_id=device["id"],
                    )
                    if force_resend:
                        deduplicator.release(dedupe_key)
                    if not deduplicator.claim(dedupe_key):
                        result["deliveries"].append(
                            {"device_id": device["id"], "status": "duplicate_skipped"}
                        )
                        continue

                    try:
                        message_id = publisher.publish(
                            endpoint_arn=device["sns_endpoint_arn"],
                            candidate=candidate,
                            content=content,
                        )
                    except ClientError as error:
                        # SNS returned an explicit provider-side failure, so no
                        # successful delivery needs protection from a retry.
                        deduplicator.release(dedupe_key)
                        error_code = error.response.get("Error", {}).get("Code", "ClientError")
                        if publisher.is_disabled_endpoint(error):
                            repository.disable_device(device["id"])
                        logger.exception(
                            "SNS publish failed user_id=%s device_id=%s code=%s",
                            user_id,
                            device["id"],
                            error_code,
                        )
                        result["deliveries"].append(
                            {
                                "device_id": device["id"],
                                "status": "failed",
                                "error_code": error_code,
                            }
                        )
                        continue
                    except ValueError as error:
                        deduplicator.release(dedupe_key)
                        logger.exception(
                            "Push payload rejected user_id=%s device_id=%s",
                            user_id,
                            device["id"],
                        )
                        result["deliveries"].append(
                            {
                                "device_id": device["id"],
                                "status": "failed",
                                "error_code": type(error).__name__,
                            }
                        )
                        continue
                    except Exception as error:  # noqa: BLE001
                        # Keep the PROCESSING claim on an ambiguous exception.
                        # A provider response may have been lost after delivery;
                        # retaining the key is safer than sending a duplicate.
                        logger.exception(
                            "Ambiguous push failure user_id=%s device_id=%s",
                            user_id,
                            device["id"],
                        )
                        result["deliveries"].append(
                            {
                                "device_id": device["id"],
                                "status": "failed_locked",
                                "error_code": type(error).__name__,
                            }
                        )
                        continue

                    try:
                        deduplicator.mark_sent(dedupe_key, message_id)
                    except Exception:  # noqa: BLE001 - delivery already succeeded
                        logger.exception(
                            "Push sent but dedupe status update failed user_id=%s device_id=%s",
                            user_id,
                            device["id"],
                        )
                    result["deliveries"].append(
                        {
                            "device_id": device["id"],
                            "status": "sent",
                            "message_id": message_id,
                        }
                    )
            results.append(result)

    sent_count = sum(
        1
        for result in results
        for delivery in result.get("deliveries", [])
        if delivery.get("status") == "sent"
    )
    response = {
        "status": "dry_run" if dry_run else "completed",
        "demo_date": demo_date.isoformat(),
        "user_count": len(results),
        "sent_count": sent_count,
        "results": results,
    }
    logger.info("Personalized push completed: %s", json.dumps(response, ensure_ascii=False))
    return response
