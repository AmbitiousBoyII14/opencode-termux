# Getting a DeepSeek API key + $2 of credit

Everything below is the official site. Ignore any YouTube video, Telegram
group or "cheap DeepSeek API" reseller — they all charge 5–20× markup.
There is no account-selling step; you do this yourself in about 5 minutes.

---

## 1. Sign up on the DEVELOPER platform

### https://platform.deepseek.com/sign_up

⚠️ **Not** `chat.deepseek.com`. That's the free chatbot. Different site,
different account. Keys only exist on `platform.`.

- Email + password, or Google sign-in
- Verify the email (check spam)
- There may be a small trial credit on the balance page — don't count on it

---

## 2. Add billing details

Left sidebar → **Top up** / **Billing**

Card needs to be **Visa or Mastercard**, debit or credit. PayPal and
Google Pay also work. Capitec, FNB, Standard Bank, Absa, Nedbank cards
are all Visa/Mastercard underneath, so they work.

**Three things that cause a decline in South Africa:**

| Cause | Fix |
|---|---|
| International online transactions disabled | Banking app → Card settings → enable "international / online purchases" |
| Card holds exactly the amount | Charged is **amount × 1.06** (6% fee/tax). A $2 top-up debits ~$2.12. Keep ~R50 headroom |
| Billing address mismatch | Type the address exactly as the bank has it |

Don't hammer retry. 2–3 failed attempts in a row locks the risk check for
a few hours. If it fails twice, wait, then try once.

---

## 3. Top up $2

**Minimum is $2.** Custom amount field, type `2`, pay.

Credit never expires. No subscription, no auto-renew — nothing charges
you again unless you press the button again.

---

## 4. Create the key

Left sidebar → **API Keys** → **Create new API key**

Name it something you'll recognise (`phone`, `opencode`).
**Copy it immediately — it is shown once.** Starts with `sk-`.

---

## 5. Test it actually works

Paste in Termux, replacing the key:

```sh
curl -s https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-YOUR_KEY_HERE" \
  -d '{"model":"deepseek-flash","messages":[{"role":"user","content":"say ok"}],"max_tokens":20}'
```

Good reply = `"content":"ok"`.

**If you get `402 Insufficient Balance`** → the top-up didn't land, or
you're on the wrong account (chat instead of platform).

**If the model name errors**, list what your account actually has:

```sh
curl -s https://api.deepseek.com/models -H "Authorization: Bearer sk-YOUR_KEY_HERE"
```

---

## 6. What $2 actually buys

DeepSeek V4.1 Flash, per 1 million tokens:

| | Peak | Off-peak (half price) |
|---|---|---|
| Input | $0.30 | **$0.15** |
| Cached input | $0.006 | $0.003 |
| Output | $1.20 | **$0.60** |

Context 1M tokens. Model ID `deepseek-flash`.

Off-peak = **everything except Mon–Fri 03:00–06:00 and 08:00–12:00 SAST.**

Real numbers: one opencode task (15 calls, ~17K context each, ~7.5K output)
costs **about $0.01 off-peak**. So $2 is roughly **150–200 real coding
sessions**. For a casual user, $2 lasts months.

---

## 7. Plug it into opencode (same proxy you already have)

No code changes. Add one line to `~/zai/keys.txt`:

```
deepseek=sk-YOUR_KEY_HERE
```

Restart the proxy (`~/zai/start.sh`), and opencode now has DeepSeek as a
fallback behind NVIDIA. To make it the primary, edit `ORDER` in
`~/zai/levi-proxy.py` so `"deepseek"` is first.

---

## Before spending the $2 — honest note

DeepSeek is the fastest and highest-quality option tested in this whole
project, and $2 genuinely lasts months. But it is **hosted inference**:
it runs DeepSeek's weights on DeepSeek's servers, not yours.

If the goal is free, the NVIDIA key already gives you
`nemotron-3-ultra-550b` at 0.6–1.8s for $0. Same trick, no card.

Pay the $2 if you want better coding answers and a 1M context window.
Don't pay it expecting to run your own model.
