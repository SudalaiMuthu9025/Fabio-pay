import asyncio
import os
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from passlib.context import CryptContext

# Fix path to import app models
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models import User, SecuritySettings, UserRole
from app.database import Base
from app.config import settings

# Password/PIN hashing
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

async def seed_admin():
    print("Initializng Fabio Admin Seeding...")
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        from sqlalchemy import select
        
        # Check if Admin already exists
        result = await session.execute(select(User).where(User.email == "admin@fabio.com"))
        existing_admin = result.scalar_one_or_none()
        
        if existing_admin:
            print("Admin user 'admin@fabio.com' already exists.")
            return

        print("Creating Admin User...")
        admin = User(
            email="admin@fabio.com",
            full_name="Fabio Admin",
            hashed_password=pwd_context.hash("admin123"),
            role=UserRole.ADMIN,
            is_active=True
        )
        session.add(admin)
        await session.flush() # get user.id
        
        print("Creating Security Settings...")
        sec = SecuritySettings(
            user_id=admin.id,
            pin_hash=pwd_context.hash("123456")
        )
        session.add(sec)
        
        await session.commit()
        print("\nSUCCESS: Admin seeded effectively.")
        print("Email: admin@fabio.com")
        print("Password: admin123")
        print("PIN: 123456")

if __name__ == "__main__":
    asyncio.run(seed_admin())
