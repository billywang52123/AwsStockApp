from sqlalchemy import Column, Integer, String, Boolean, Date
from app.db.database import Base

class AchievementModel(Base):
    __tablename__ = "achievements"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, index=True, default="demo-user")
    achievement_key = Column(String, index=True)
    title = Column(String)
    description = Column(String)
    icon_name = Column(String)
    is_unlocked = Column(Boolean, default=False)
    unlocked_at = Column(Date, nullable=True)
