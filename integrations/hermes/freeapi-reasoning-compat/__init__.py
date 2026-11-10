"""Temporary, endpoint-scoped workaround for Hermes issue #136486.

Only the FreeAPI DeepSeek wire copy changes; stored history is untouched.
Disable with `hermes plugins disable freeapi-reasoning-compat`, then restart Hermes.
No credentials, network services, or repository modifications are required.
"""

from functools import wraps
from urllib.parse import urlsplit


def _single_carrier(route, model, base_url):
    try:
        url = urlsplit(str(base_url or ''))
        is_freeapi = (
            url.scheme == 'http'
            and url.hostname in {'127.0.0.1', 'localhost', '::1'}
            and url.port == 18189
            and url.path.rstrip('/') == '/v1'
        )
    except ValueError:
        is_freeapi = False
    if (is_freeapi and str(model).lower() == 'deepseek-v4.1-flash'
            and route.carriers is not None and 'reasoning_content' in route.carriers):
        return route._replace(carriers=route.carriers - {'reasoning'})
    return route


def register(ctx):
    from agent import message_sanitization as policy
    from agent.reasoning_params import ReasoningParamsMixin

    original = policy.reasoning_replay_route
    if not getattr(original, '_freeapi_single_reasoning', False):
        @wraps(original)
        def single_reasoning(api_mode, provider, model, base_url, **kwargs):
            route = original(api_mode, provider, model, base_url, **kwargs)
            return _single_carrier(route, model, base_url)

        single_reasoning._freeapi_single_reasoning = True
        policy.reasoning_replay_route = single_reasoning

    # Existing gateway sessions cache the old route. Normalize the returned value too,
    # so a plugin reload fixes those sessions without discarding or rewriting history.
    original_method = ReasoningParamsMixin._reasoning_replay_route
    if not getattr(original_method, '_freeapi_single_reasoning', False):
        @wraps(original_method)
        def cached_route(agent):
            return _single_carrier(original_method(agent), agent.model, agent.base_url)

        cached_route._freeapi_single_reasoning = True
        ReasoningParamsMixin._reasoning_replay_route = cached_route
