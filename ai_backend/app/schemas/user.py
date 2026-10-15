from pydantic import BaseModel


class AuthenticatedUser(BaseModel):
    id: str
    email: str | None = None
    role: str | None = None
    assurance_level: str = "aal1"