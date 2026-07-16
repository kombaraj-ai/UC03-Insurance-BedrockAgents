import sys
from pathlib import Path

import pytest

SRC_DIR = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("KNOWLEDGE_BASE_ID", "KB123456")
    monkeypatch.setenv("DATA_SOURCE_ID", "DS123456")
