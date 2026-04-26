"""
Fabio Backend — Analytics Router
==================================
GET /analytics/spending-summary — weekly/monthly spending breakdown
"""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends, status
from sqlalchemy import select, func, case, cast, Date, String
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import Transaction, TransactionStatus, TransactionType, User
from app.schemas import DailySpending, MonthlySpending, SpendingSummary

router = APIRouter(prefix="/analytics", tags=["Analytics"])


@router.get(
    "/spending-summary",
    response_model=SpendingSummary,
    summary="Get weekly and monthly spending breakdown",
)
async def spending_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.utcnow()
    week_ago = now - timedelta(days=7)
    six_months_ago = now - timedelta(days=180)

    # ── Daily breakdown (last 7 days) ────────────────────────────────────
    daily_result = await db.execute(
        select(
            cast(Transaction.created_at, Date).label("day"),
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.DEBIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("sent"),
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.CREDIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("received"),
        )
        .where(
            Transaction.user_id == current_user.id,
            Transaction.status == TransactionStatus.SUCCESS,
            Transaction.created_at >= week_ago,
        )
        .group_by(cast(Transaction.created_at, Date))
        .order_by(cast(Transaction.created_at, Date))
    )

    weekly = []
    for row in daily_result:
        weekly.append(DailySpending(
            date=str(row.day),
            sent=row.sent or Decimal("0"),
            received=row.received or Decimal("0"),
        ))

    # Fill missing days with zeros
    existing_dates = {d.date for d in weekly}
    for i in range(7):
        day = (now - timedelta(days=6 - i)).strftime("%Y-%m-%d")
        if day not in existing_dates:
            weekly.append(DailySpending(date=day, sent=Decimal("0"), received=Decimal("0")))
    weekly.sort(key=lambda d: d.date)

    # ── Monthly breakdown (last 6 months) ────────────────────────────────
    monthly_result = await db.execute(
        select(
            func.to_char(Transaction.created_at, 'YYYY-MM').label("month"),
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.DEBIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("sent"),
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.CREDIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("received"),
        )
        .where(
            Transaction.user_id == current_user.id,
            Transaction.status == TransactionStatus.SUCCESS,
            Transaction.created_at >= six_months_ago,
        )
        .group_by(func.to_char(Transaction.created_at, 'YYYY-MM'))
        .order_by(func.to_char(Transaction.created_at, 'YYYY-MM'))
    )

    monthly = []
    for row in monthly_result:
        monthly.append(MonthlySpending(
            month=row.month,
            sent=row.sent or Decimal("0"),
            received=row.received or Decimal("0"),
        ))

    # ── Totals ────────────────────────────────────────────────────────────
    totals_result = await db.execute(
        select(
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.DEBIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("total_sent"),
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.transaction_type == TransactionType.CREDIT, Transaction.amount),
                        else_=Decimal("0"),
                    )
                ),
                Decimal("0"),
            ).label("total_received"),
        )
        .where(
            Transaction.user_id == current_user.id,
            Transaction.status == TransactionStatus.SUCCESS,
        )
    )
    totals = totals_result.one()

    return SpendingSummary(
        weekly=weekly,
        monthly=monthly,
        total_sent=totals.total_sent or Decimal("0"),
        total_received=totals.total_received or Decimal("0"),
    )
