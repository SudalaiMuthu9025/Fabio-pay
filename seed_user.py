import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from passlib.context import CryptContext

# Configuration
DATABASE_URL = "postgresql+asyncpg://fabio:fabio@localhost:5432/fabio_db"
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

async def seed_user():
    from app.models import User, SecuritySettings, UserRole
    from app.database import Base
    
    engine = create_async_engine(DATABASE_URL)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Check if user exists
        from sqlalchemy import select
        result = await session.execute(select(User).where(User.email == "admin@fabio.com"))
        if result.scalar_one_or_none():
            print("Admin user already exists.")
            return

        # Create user
        user = User(
            email="admin@fabio.com",
            full_name="Fabio Admin",
            hashed_password=pwd_context.hash("admin123"),
            role=UserRole.ADMIN
        )
        session.add(user)
        await session.flush()
        
        # Create security settings
        sec = SecuritySettings(
            user_id=user.id,
            pin_hash=pwd_context.hash("123456")
        )
        session.add(sec)
        await session.commit()
        print("Admin user created: email: admin@fabio.com, password: admin123, pin: 123456")

if __name__ == "__main__":
    import os
    import sys
    # Add backend to path to import app.models
    sys.path.append(os.path.join(os.getcwd(), "backend"))
    asyncio.run(seed_user())
