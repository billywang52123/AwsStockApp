from unittest.mock import MagicMock, patch

import scripts.seed_demo_data as seed_mod


def test_seed_skips_when_stocks_exist():
    fake_db = MagicMock()
    fake_db.query.return_value.count.return_value = 5  # 已有股票
    with patch.object(seed_mod, "SessionLocal", return_value=fake_db), \
         patch.object(seed_mod.Base.metadata, "create_all"), \
         patch("app.db.migrations.run_light_migrations"):
        did_seed = seed_mod.seed()
    assert did_seed is False
    fake_db.commit.assert_not_called()
