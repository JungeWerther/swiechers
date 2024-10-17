#!/bin/bash
PROJECT_REF=$(grep PROJECT_REF= ~/sites/swiechers/.env.local | cut -d '=' -f2)
npx supabase gen types --lang=typescript --project-id "$PROJECT_REF" --schema=public > database.types.ts