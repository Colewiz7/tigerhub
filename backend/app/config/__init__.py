"""Static configuration: post offices, SHED hours, residence hall addresses."""

from app.config.static import (
    ConfigError,
    StaticConfig,
    get_config,
    load_config,
    staleness_report,
)

__all__ = [
    "ConfigError",
    "StaticConfig",
    "get_config",
    "load_config",
    "staleness_report",
]
