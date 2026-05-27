/speckit-implement Implement phase(s) {{phases}} from @{{task}} only. I will review afterwards.

For frontend changes, run flutter analyze and fix all issues.

If any backend migrations need to be done execute before running any test cases:
>> cd backend
>> supabase migration up

Assess the changes introduced:
- If they are frontend-only and have no communication with the backend, implement frontend unit test cases
- If it is backend only and is not exposed to communication with the frontend: implement backend unit test cases
- If the changes are in the backend or frontend but will affect their communication, implement unit test cases and integration tets.

Implement detailed test cases, even more than what is described in md file:
- trivial
- advanced
- stupid user usage
- edge cases
- invalid states
- regression scenarios

When finished:
- if the changes are frontend related only, run ALL frontend tests using run_all_tests.py [takes around 10 minutes]
- if the changes are backend tests only, run ALL backend tests using run_all_backend_tests.sh and run integration tests using run_boundary_tests.py [takes around 5 minutes]
- do not exit untill all tests pass

Follow clean architecture Flutter practices, and secure backend practices.