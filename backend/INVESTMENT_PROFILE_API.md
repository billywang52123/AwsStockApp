# Investment Profile API

Base path: `/api/investment-profile`. All endpoints use the existing authenticated `user_id`; one user's questionnaire and history are never shared with another user.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/questionnaire` | Questionnaire definition, completion state, current answers |
| `PUT` | `/questionnaire` | Save all six answers and recalculate preference style |
| `GET` | `` | Current preference style, observed style, habit and live portfolio metrics |
| `GET` | `/history?limit=30` | Style/habit snapshots, newest first |
| `POST` | `/refresh` | Manually create a fresh habit snapshot |
| `GET` | `/prompt-context` | Structured style context and generated prompt text for AI analysis |

Holding add/delete/buy/sell/override/restore/import and activity deletion automatically create history snapshots. Frontend does not need to call `/refresh` after normal holding changes.

## Questionnaire body

```json
{
  "investment_horizon": "long",
  "risk_tolerance": "balanced",
  "decision_style": "data_driven",
  "trading_frequency": "low",
  "drawdown_response": "review",
  "primary_goal": "growth"
}
```

Allowed codes and display copy are returned by `GET /questionnaire`; the frontend should render that response rather than duplicate option text.

## Style semantics

- `preference_style`: self-reported questionnaire preference.
- `observed_style`: style inferred from current concentration, industry exposure and 30-day activity.
- `investment_habit`: plain-language description of actual holdings behavior.

These are intentionally separate. A user can prefer a balanced approach while their current portfolio is observed as concentrated.

## Existing insight response

`GET /api/insights/{symbol}` keeps all existing fields and adds:

```json
{
  "personalization": {
    "prompt_version": "investment-context-v1",
    "preference_style": {},
    "observed_style": {},
    "investment_habit": {},
    "title": "...",
    "summary": "...",
    "sections": [
      {"key": "style", "title": "從問卷偏好看", "text": "..."},
      {"key": "habit", "title": "從實際持股習慣看", "text": "..."},
      {"key": "market", "title": "和市場資料合併看", "text": "..."}
    ],
    "observation_points": [],
    "data_date": "2025-07-14"
  }
}
```

The daily-pack AI prompt also receives this profile context. It may change explanation order and depth, but the existing restrictions remain: no price prediction, return promise, or trading instruction.
