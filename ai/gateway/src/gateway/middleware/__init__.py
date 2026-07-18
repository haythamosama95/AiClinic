"""Gateway ASGI middleware."""

from gateway.middleware.observability import ObservabilityMiddleware

__all__ = ["ObservabilityMiddleware"]
