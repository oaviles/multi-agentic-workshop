# Copyright (c) Microsoft. All rights reserved.
"""Environment driven configuration for the A2A agent service.

All configuration is read from environment variables so that the same image can
run locally (``.env`` file) and in Azure Container Apps (container app
environment variables and secrets).
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from urllib.parse import urlparse

from dotenv import load_dotenv

load_dotenv(override=False)

_TRUE_VALUES = {"1", "true", "yes", "on"}


def _get_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in _TRUE_VALUES


def _get_str(name: str, default: str = "") -> str:
    value = os.environ.get(name)
    if value is None or value.strip() == "":
        return default
    return value.strip()


def _get_list(name: str) -> list[str]:
    return [item.strip() for item in _get_str(name).split(",") if item.strip()]


@dataclass(frozen=True)
class AzureOpenAISettings:
    """Model connection settings (Azure OpenAI / Azure AI Foundry)."""

    endpoint: str = field(default_factory=lambda: _get_str("AZURE_OPENAI_ENDPOINT"))
    deployment_name: str = field(default_factory=lambda: _get_str("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o-mini"))
    api_version: str = field(default_factory=lambda: _get_str("AZURE_OPENAI_API_VERSION", "v1"))
    api_key: str = field(default_factory=lambda: _get_str("AZURE_OPENAI_API_KEY"))

    @property
    def use_managed_identity(self) -> bool:
        """Use Entra ID (managed identity / developer credential) when no API key is configured."""
        return not self.api_key

    def validate(self) -> None:
        if not self.endpoint:
            raise ValueError("AZURE_OPENAI_ENDPOINT must be set to run the agent against a model.")
        if not self.deployment_name:
            raise ValueError("AZURE_OPENAI_DEPLOYMENT_NAME must be set to run the agent against a model.")


@dataclass(frozen=True)
class Agent365Settings:
    """Microsoft 365 Agent SDK (Agent 365) settings."""

    enabled: bool = field(default_factory=lambda: _get_bool("AGENT365_ENABLED", True))
    #: When enabled, inbound A2A calls must carry a valid Entra ID bearer token.
    require_auth: bool = field(default_factory=lambda: _get_bool("AGENT365_REQUIRE_AUTH", True))
    client_id: str = field(default_factory=lambda: _get_str("AGENT365_CLIENT_ID"))
    tenant_id: str = field(default_factory=lambda: _get_str("AGENT365_TENANT_ID"))
    client_secret: str = field(default_factory=lambda: _get_str("AGENT365_CLIENT_SECRET"))
    #: Optional allow-list of caller application ids (``appid``/``azp`` claim), comma separated.
    #: Empty means any caller with a valid token for this agent's audience is accepted.
    authorized_callers: list[str] = field(default_factory=lambda: _get_list("AGENT365_AUTHORIZED_CALLERS"))
    #: Issuers accepted on inbound tokens (comma separated); empty means SDK defaults.
    issuers: list[str] = field(default_factory=lambda: _get_list("AGENT365_ISSUERS"))
    validate_issuer: bool = field(default_factory=lambda: _get_bool("AGENT365_VALIDATE_ISSUER", True))


@dataclass(frozen=True)
class Settings:
    """Top level service settings."""

    agent_name: str = field(default_factory=lambda: _get_str("AGENT_NAME", "Anne Agent"))
    agent_description: str = field(
        default_factory=lambda: _get_str(
            "AGENT_DESCRIPTION",
            "An A2A-enabled enterprise assistant built with the Microsoft Agent Framework.",
        )
    )
    agent_version: str = field(default_factory=lambda: _get_str("AGENT_VERSION", "1.0.0"))
    agent_instructions: str = field(
        default_factory=lambda: _get_str(
            "AGENT_INSTRUCTIONS",
            (
                "You are Anne Agent, a helpful enterprise assistant. Answer clearly and concisely, "
                "use the available tools whenever they can provide factual information, and "
                "state plainly when you do not know something."
            ),
        )
    )
    host: str = field(default_factory=lambda: _get_str("HOST", "0.0.0.0"))  # noqa: S104 - container ingress
    port: int = field(default_factory=lambda: int(_get_str("PORT", "8000")))
    log_level: str = field(default_factory=lambda: _get_str("LOG_LEVEL", "INFO").upper())
    #: Public HTTPS base URL of the container app, published in the agent card.
    public_base_url: str = field(default_factory=lambda: _get_str("PUBLIC_BASE_URL", "http://localhost:8000"))
    #: Path of the A2A JSON-RPC endpoint.
    a2a_path: str = field(default_factory=lambda: _get_str("A2A_PATH", "/a2a/v1"))
    #: Stream agent responses as A2A artifact updates.
    a2a_streaming: bool = field(default_factory=lambda: _get_bool("A2A_STREAMING", True))
    #: Accept A2A v0.3 method names (``message/send``) on the same endpoint, which
    #: keeps compatibility with clients that have not moved to the 1.0 methods yet.
    a2a_v03_compat: bool = field(default_factory=lambda: _get_bool("A2A_V03_COMPAT", True))
    #: Explicit escape hatch for intentionally public non-local development endpoints.
    allow_anonymous_a2a: bool = field(default_factory=lambda: _get_bool("ALLOW_ANONYMOUS_A2A", False))

    azure_openai: AzureOpenAISettings = field(default_factory=AzureOpenAISettings)
    agent365: Agent365Settings = field(default_factory=Agent365Settings)

    @property
    def a2a_url(self) -> str:
        """Absolute URL of the A2A endpoint as advertised in the agent card."""
        return f"{self.public_base_url.rstrip('/')}{self.a2a_path}"

    def validate_security(self) -> None:
        """Reject unsafe authentication settings for non-local endpoints."""
        public_url = urlparse(self.public_base_url)
        is_local = public_url.hostname in {"localhost", "127.0.0.1", "::1"}

        if not is_local and public_url.scheme != "https":
            raise ValueError("PUBLIC_BASE_URL must use HTTPS for non-local endpoints.")
        if self.agent365.require_auth and not self.agent365.enabled:
            raise ValueError("AGENT365_ENABLED must be true when AGENT365_REQUIRE_AUTH is true.")
        if self.agent365.require_auth and not self.agent365.validate_issuer:
            raise ValueError("AGENT365_VALIDATE_ISSUER must be true when authentication is required.")
        if not is_local and not self.allow_anonymous_a2a and not (
            self.agent365.enabled and self.agent365.require_auth
        ):
            raise ValueError(
                "Public A2A endpoints must require Agent 365 authentication. "
                "Set ALLOW_ANONYMOUS_A2A=true only for an intentional public development endpoint."
            )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide settings singleton."""
    return Settings()
