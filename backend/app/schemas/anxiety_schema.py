from pydantic import BaseModel, ConfigDict

class AnxietyResultRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    score: int
    level: str
    message: str
    main_reason: str
    risk_label: str
