import sys
from pathlib import Path

import pytest

SRC_DIR = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AGENT_ID", "AGENT123")
    monkeypatch.setenv("AGENT_ALIAS_ID", "ALIAS123")


class FakeBedrockAgentRuntime:
    """boto3's InvokeAgent response streams via a real EventStream object,
    which botocore's Stubber does not model well. Since
    _extract_completion_text only needs an iterable of event dicts (which is
    exactly what iterating a real EventStream yields), a plain fake client
    returning a plain list is a faithful, much simpler stand-in than trying
    to fabricate a real EventStream through Stubber.
    """

    def __init__(self, completion_events=None, error=None):
        self.completion_events = completion_events or []
        self.error = error
        self.last_kwargs = None

    def invoke_agent(self, **kwargs):
        self.last_kwargs = kwargs
        if self.error is not None:
            raise self.error
        return {"completion": self.completion_events}


@pytest.fixture
def fake_bedrock(monkeypatch):
    import handler

    fake = FakeBedrockAgentRuntime(
        completion_events=[
            {"chunk": {"bytes": b"Hello "}},
            {"chunk": {"bytes": b"world."}},
        ]
    )
    monkeypatch.setattr(handler, "_bedrock_agent_runtime", fake)
    return fake
