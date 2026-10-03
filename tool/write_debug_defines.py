"""Create private test-build configuration without printing its secret."""
import json
import os
from pathlib import Path
import sys
import uuid


def build_defines(token):
    token = token.strip()
    if token:
        try:
            parsed = uuid.UUID(token)
        except ValueError:
            raise ValueError('AGRO_APP_CHECK_DEBUG_TOKEN must be a UUID v4') from None
        if parsed.version != 4 or str(parsed) != token.lower():
            raise ValueError('AGRO_APP_CHECK_DEBUG_TOKEN must be a canonical UUID v4')
    return {'AGRO_APP_CHECK_DEBUG': True, 'AGRO_APP_CHECK_DEBUG_TOKEN': token}


if __name__ == '__main__':
    config = build_defines(os.environ.get('AGRO_APP_CHECK_DEBUG_TOKEN', ''))
    Path(sys.argv[1]).write_text(json.dumps(config), encoding='utf-8')
