# Global GG Coder Config

## Subagent Routing
- Use the model specified in each agent's definition. Don't override.
- If a subagent returns confused or low-quality results, escalate one tier up — don't retry at the same tier.

## Preferences
- NEVER use EnterPlanMode. Use the /plan-checkpoint skill instead when planning is needed.
