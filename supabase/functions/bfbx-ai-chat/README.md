# BFB AI chat

BFB AI is a read-only chat assistant for approved BFB X Tracker members.

## Deployment
- Supabase project: `wlxilsrypqrscjanbsgh`
- Edge Function: `bfbx-ai-chat`
- JWT verification: enabled
- Model: `gpt-5.4-mini`
- The function reads tracker data with the caller's authenticated Supabase session and existing RLS policies. It does not use the service-role key or write to tracker tables.

## Required secret
In Supabase Dashboard → Project Settings → Edge Function Secrets, add:

- Name: `OPENAI_API_KEY`
- Value: an OpenAI API key created in the OpenAI Platform

Never place the OpenAI key in `index.html`, other browser JavaScript, or GitHub. The browser calls the Edge Function through the Supabase client; the OpenAI key stays server-side.

## Access
Only signed-in admins and approved viewers can use the assistant. New/unapproved accounts receive an access message. Chat history is kept in the open browser page only and is not stored in the database.

## GitHub Pages
The floating BFB AI panel is included in the repository root `index.html`. GitHub Pages should be configured to publish the `main` branch from the repository root.
