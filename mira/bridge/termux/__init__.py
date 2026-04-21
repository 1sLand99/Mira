"""Termux(安卓终端环境) 相关 PTY 能力封装。"""

from .pty_session import PtySession, resolve_shell

__all__ = ["PtySession", "resolve_shell"]
