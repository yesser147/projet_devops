from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from app.database import supabase
from app.models import (
    StudentProfile,
    StudentUpdate,
    Recommendation,
    FeedbackSubmit,
    RecommendationRequest
)
from app.recommender import recommender_engine
from app.cf_recommender import cf_recommender
from typing import List
import json

app = FastAPI(title="Study Program Recommender API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    result = supabase.table("programs").select("*").execute()
    programs = result.data
    if programs:
        recommender_engine.fit(programs)
    # try to fit collaborative model (uses feedback/recommendations tables)
    try:
        cf_recommender.fit()
    except Exception:
        # don't block startup if CF fails
        pass

@app.get("/")
def read_root():
    return {"message": "Study Program Recommender API", "status": "running"}

@app.get("/programs")
def get_programs():
    try:
        result = supabase.table("programs").select("*").execute()
        return {"programs": result.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/students")
def create_student(student: StudentProfile):
    try:
        existing = supabase.table("students").select("*").eq("email", student.email).execute()

        if existing.data:
            raise HTTPException(status_code=400, detail="Student with this email already exists")

        result = supabase.table("students").insert({
            "name": student.name,
            "email": student.email,
            "interests": student.interests,
            "grades": student.grades
        }).execute()

        return {"student": result.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/students/{student_id}")
def get_student(student_id: str):
    try:
        result = supabase.table("students").select("*").eq("id", student_id).execute()

        if not result.data:
            raise HTTPException(status_code=404, detail="Student not found")

        return {"student": result.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/students/{student_id}")
def update_student(student_id: str, student_update: StudentUpdate):
    try:
        update_data = {}
        if student_update.name is not None:
            update_data["name"] = student_update.name
        if student_update.interests is not None:
            update_data["interests"] = student_update.interests
        if student_update.grades is not None:
            update_data["grades"] = student_update.grades

        if not update_data:
            raise HTTPException(status_code=400, detail="No fields to update")

        update_data["updated_at"] = "now()"

        result = supabase.table("students").update(update_data).eq("id", student_id).execute()

        if not result.data:
            raise HTTPException(status_code=404, detail="Student not found")

        return {"student": result.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/recommendations", response_model=List[Recommendation])
def get_recommendations(request: RecommendationRequest):
    try:
        student_result = supabase.table("students").select("*").eq("id", request.student_id).execute()

        if not student_result.data:
            raise HTTPException(status_code=404, detail="Student not found")

        student_data = student_result.data[0]

        programs_result = supabase.table("programs").select("*").execute()
        programs = programs_result.data

        if not programs:
            return []

        recommender_engine.fit(programs)

        content_recs = recommender_engine.recommend(
            student_data,
            top_k=request.top_k
        )

        # Get CF scores (if available) and combine with content scores
        try:
            cf_scores = cf_recommender.recommend_for_student(request.student_id, programs, top_k=request.top_k)
        except Exception:
            cf_scores = {}

        alpha = 0.6

        response_recommendations = []
        for program, content_score, explanation in content_recs:
            pid = program['id']
            cf_score = cf_scores.get(pid, 0.0)
            final_score = float(alpha * content_score + (1 - alpha) * cf_score)

            rec_data = {
                "student_id": request.student_id,
                "program_id": pid,
                "score": final_score,
                "explanation": explanation,
                "algorithm": "hybrid"
            }

            try:
                supabase.table("recommendations").insert(rec_data).execute()
            except Exception:
                pass

            response_recommendations.append(
                Recommendation(
                    program_id=pid,
                    program_name=program['name'],
                    program_description=program['description'],
                    score=final_score,
                    explanation=explanation,
                    tags=program.get('tags', []),
                    skills=program.get('skills', [])
                )
            )

        return response_recommendations

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/feedback")
def submit_feedback(student_id: str, feedback: FeedbackSubmit):
    try:
        feedback_data = {
            "student_id": student_id,
            "program_id": feedback.program_id,
            "clicked": feedback.clicked,
            "accepted": feedback.accepted
        }

        if feedback.rating is not None:
            if feedback.rating < 1 or feedback.rating > 5:
                raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")
            feedback_data["rating"] = feedback.rating

        result = supabase.table("feedback").insert(feedback_data).execute()

        # optionally trigger a background retrain signal (lightweight)
        try:
            cf_recommender.fit()
        except Exception:
            pass

        return {"feedback": result.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/retrain")
def retrain_models():
    try:
        cf_recommender.fit()
        return {"status": "ok", "cf_trained": cf_recommender.fitted}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/students/{student_id}/recommendations")
def get_student_recommendations(student_id: str):
    try:
        result = supabase.table("recommendations").select(
            "*, programs(*)"
        ).eq("student_id", student_id).order("created_at", desc=True).limit(10).execute()

        return {"recommendations": result.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
