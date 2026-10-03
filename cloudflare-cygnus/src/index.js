const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_TRANSCRIBE_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const ALLOWED_MODELS = new Set([
  'openai/gpt-oss-120b',
  'openai/gpt-oss-20b',
]);
const ALLOWED_REASONING = new Set(['low', 'medium', 'high']);
const ALLOWED_TOOLS = new Set([
  'get_current_context',
  'get_current_status',
  'get_metric_trend',
  'set_motor',
  'set_all_motors',
  'list_schedules',
  'prepare_schedule',
  'prepare_update_schedule',
  'confirm_pending_action',
  'cancel_pending_action',
  'set_schedule_enabled',
  'prepare_delete_schedule',
  'get_last_leaf_result',
  'open_page',
]);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Cache-Control': 'no-store',
};

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') {
      return json({
        ok: true,
        service: 'cygnus-gateway',
        models: [env.FAST_MODEL || 'openai/gpt-oss-20b', env.PRIMARY_MODEL || 'openai/gpt-oss-120b'],
        voiceModel: env.STT_MODEL || 'whisper-large-v3',
        authRequired: env.REQUIRE_FIREBASE_AUTH === 'true',
      });
    }

    if (request.method !== 'POST') {
      return error(404, 'not_found', 'Route not found.');
    }
    if (!env.GROQ_API_KEY) {
      return error(503, 'gateway_not_configured', 'GROQ_API_KEY is not configured.');
    }

    if (env.REQUIRE_FIREBASE_AUTH === 'true') {
      const auth = request.headers.get('Authorization') || '';
      const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
      if (!token) return error(401, 'unauthorized', 'Missing app session token.');
      const verified = await verifyFirebaseToken(token, env);
      if (!verified) return error(401, 'unauthorized', 'Invalid app session token.');
    }

    if (url.pathname === '/v1/transcribe') {
      return transcribeVoice(request, env);
    }
    if (url.pathname !== '/v1/chat') {
      return error(404, 'not_found', 'Route not found.');
    }

    const contentLength = Number(request.headers.get('content-length') || '0');
    if (contentLength > 180_000) {
      return error(413, 'payload_too_large', 'Request is too large.');
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return error(400, 'invalid_json', 'Invalid JSON body.');
    }

    const model = ALLOWED_MODELS.has(body.model)
      ? body.model
      : (env.PRIMARY_MODEL || 'openai/gpt-oss-120b');
    const reasoning = ALLOWED_REASONING.has(body.reasoning_effort)
      ? body.reasoning_effort
      : 'low';

    const messages = sanitizeMessages(body.messages);
    if (!messages.length) return error(400, 'invalid_messages', 'No valid messages provided.');

    const tools = sanitizeTools(body.tools);
    const payload = {
      model,
      messages,
      tools,
      tool_choice: tools.length ? 'auto' : undefined,
      parallel_tool_calls: false,
      reasoning_effort: reasoning,
      reasoning_format: 'hidden',
      temperature: 0.2,
      max_completion_tokens: 700,
    };
    Object.keys(payload).forEach((key) => payload[key] === undefined && delete payload[key]);

    let upstream;
    try {
      upstream = await fetch(GROQ_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.GROQ_API_KEY}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify(payload),
      });
    } catch (_) {
      return error(502, 'groq_unreachable', 'The AI provider could not be reached.');
    }

    const raw = await upstream.text();
    let decoded;
    try {
      decoded = JSON.parse(raw);
    } catch (_) {
      decoded = null;
    }

    if (!upstream.ok) {
      const providerMessage = decoded?.error?.message || 'AI provider request failed.';
      if (upstream.status === 429) {
        return error(429, 'rate_limit', 'Cygnus is busy right now. Try again shortly.');
      }
      return error(upstream.status >= 500 ? 502 : 400, 'provider_error', providerMessage);
    }

    return new Response(JSON.stringify(decoded), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
    });
  },
};

async function transcribeVoice(request, env) {
  const contentLength = Number(request.headers.get('content-length') || '0');
  if (contentLength > 12_000_000) {
    return error(413, 'audio_too_large', 'Voice message is too large.');
  }

  let incoming;
  try {
    incoming = await request.formData();
  } catch (_) {
    return error(400, 'invalid_audio', 'Invalid voice upload.');
  }

  const file = incoming.get('file');
  if (!(file instanceof File) || file.size === 0) {
    return error(400, 'missing_audio', 'No voice recording was provided.');
  }

  const languageCode = String(incoming.get('language_code') || 'en').toLowerCase();
  const prompts = {
    ta: 'Tamil, Tanglish and Indian English farm-control speech. Preserve the words actually spoken. Common terms: Cygnus, Agro Connect, motor one/two/three, rendu, moonu, start pannuda, off pannidu, ippo, adha, naalaikku, mani, evlo neram, temperature, humidity, soil moisture, water level, schedule, plan, leaf, treatment, prevention.',
    hi: 'Hindi, Hinglish and Indian English farm-control speech. Preserve the words actually spoken. Common terms: Cygnus, Agro Connect, motor 1/2/3, chalu karo, band karo, abhi, kal, temperature, humidity, soil moisture, water level, schedule, plant health, treatment, prevention.',
    ml: 'Malayalam, Manglish and Indian English farm-control speech. Preserve the words actually spoken. Common terms: Cygnus, Agro Connect, motor 1/2/3, on, off, ippo, nale, temperature, humidity, soil moisture, water level, schedule, plant health, treatment, prevention.',
    kn: 'Kannada, Kanglish and Indian English farm-control speech. Preserve the words actually spoken. Common terms: Cygnus, Agro Connect, motor 1/2/3, on, off, ivaga, nale, temperature, humidity, soil moisture, water level, schedule, plant health, treatment, prevention.',
    en: 'Indian English plus Tamil-English Tanglish farm-control speech. Preserve the words actually spoken instead of translating them. Common phrases: motor 2 start pannuda, adha off pannidu, current temperature enna, naalaikku 7 mani, rendu minutes, evlo neram, soil moisture, water level, schedule, Cygnus, Agro Connect, leaf treatment, preventive measures.',
  };

  const form = new FormData();
  form.append('file', file, file.name || 'cygnus-voice.m4a');
  form.append('model', env.STT_MODEL || 'whisper-large-v3');
  form.append('response_format', 'json');
  form.append('temperature', '0');
  form.append('prompt', prompts[languageCode] || prompts.en);
  // Language is intentionally not forced. Tanglish and other mixed-language
  // utterances are better handled with Whisper auto-detection plus vocabulary hints.

  let upstream;
  try {
    upstream = await fetch(GROQ_TRANSCRIBE_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.GROQ_API_KEY}`,
        'Accept': 'application/json',
      },
      body: form,
    });
  } catch (_) {
    return error(502, 'voice_unreachable', 'Voice recognition could not be reached.');
  }

  const raw = await upstream.text();
  let decoded = null;
  try { decoded = JSON.parse(raw); } catch (_) {}

  if (!upstream.ok) {
    const message = decoded?.error?.message || 'Voice recognition failed.';
    if (upstream.status === 429) {
      return error(429, 'voice_rate_limit', 'Voice recognition is busy. Try again shortly.');
    }
    return error(upstream.status >= 500 ? 502 : 400, 'voice_provider_error', message);
  }

  const textValue = String(decoded?.text || '').trim();
  return json({ ok: true, text: textValue, model: env.STT_MODEL || 'whisper-large-v3' });
}

async function verifyFirebaseToken(idToken, env) {
  if (!env.FIREBASE_API_KEY) return false;
  try {
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken }),
      },
    );
    if (!response.ok) return false;
    const data = await response.json();
    return Array.isArray(data.users) && data.users.length > 0;
  } catch (_) {
    return false;
  }
}

function sanitizeMessages(value) {
  if (!Array.isArray(value)) return [];
  const allowedRoles = new Set(['system', 'user', 'assistant', 'tool']);
  const items = [];
  for (const raw of value.slice(-30)) {
    if (!raw || typeof raw !== 'object') continue;
    const role = String(raw.role || '');
    if (!allowedRoles.has(role)) continue;

    const item = { role };
    if (raw.content === null || typeof raw.content === 'string') {
      item.content = raw.content;
    } else {
      item.content = String(raw.content ?? '');
    }

    if (role === 'assistant' && Array.isArray(raw.tool_calls)) {
      item.tool_calls = raw.tool_calls
        .slice(0, 8)
        .map(sanitizeToolCall)
        .filter(Boolean);
    }
    if (role === 'tool') {
      item.tool_call_id = String(raw.tool_call_id || '').slice(0, 180);
      item.name = String(raw.name || '').slice(0, 80);
    }
    items.push(item);
  }

  const charCount = items.reduce((sum, m) => sum + JSON.stringify(m).length, 0);
  if (charCount > 140_000) {
    return items.slice(-16);
  }
  return items;
}

function sanitizeToolCall(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const fn = raw.function;
  if (!fn || typeof fn !== 'object') return null;
  const name = String(fn.name || '');
  if (!ALLOWED_TOOLS.has(name)) return null;
  return {
    id: String(raw.id || '').slice(0, 180),
    type: 'function',
    function: {
      name,
      arguments: typeof fn.arguments === 'string' ? fn.arguments : '{}',
    },
  };
}

function sanitizeTools(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((tool) => {
      if (!tool || tool.type !== 'function') return false;
      const name = tool.function?.name;
      return typeof name === 'string' && ALLOWED_TOOLS.has(name);
    })
    .map((tool) => ({
      type: 'function',
      function: {
        name: tool.function.name,
        description: String(tool.function.description || '').slice(0, 900),
        parameters: tool.function.parameters || { type: 'object', properties: {} },
      },
    }));
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function error(status, code, message) {
  return json({ error: { code, message } }, status);
}
