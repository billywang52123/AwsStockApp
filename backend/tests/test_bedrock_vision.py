from unittest.mock import MagicMock, patch

from app.services.bedrock_vision_service import BedrockVisionService


def _fake_converse_response(text: str):
    return {"output": {"message": {"content": [{"text": text}]}}}


def test_extract_receipt_text_returns_model_text():
    fake_client = MagicMock()
    fake_client.converse.return_value = _fake_converse_response('{"stocks": []}')
    with patch.object(BedrockVisionService, "_client", return_value=fake_client):
        out = BedrockVisionService.extract_receipt_text(b"\x89PNG...", "image/png")
    assert out == '{"stocks": []}'
    # 送出的影像格式要對應 png
    _, kwargs = fake_client.converse.call_args
    img_block = kwargs["messages"][0]["content"][0]["image"]
    assert img_block["format"] == "png"
    assert img_block["source"]["bytes"] == b"\x89PNG..."


def test_jpeg_content_type_maps_to_jpeg():
    fake_client = MagicMock()
    fake_client.converse.return_value = _fake_converse_response("{}")
    with patch.object(BedrockVisionService, "_client", return_value=fake_client):
        BedrockVisionService.extract_receipt_text(b"\xff\xd8\xff", "image/jpeg")
    _, kwargs = fake_client.converse.call_args
    assert kwargs["messages"][0]["content"][0]["image"]["format"] == "jpeg"
