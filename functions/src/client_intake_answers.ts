export const intakeFields = {
  full_name: { label: "Full name", max: 160 },
  age: { label: "Age", max: 3 },
  date_of_birth: { label: "Date of birth", max: 10 },
  contact_email: { label: "Contact email", max: 254 },
  contact_phone: { label: "Contact phone", max: 32 },
  height_cm: { label: "Height", max: 16, minValue: 30, maxValue: 300 },
  weight_kg: { label: "Weight", max: 16, minValue: 1, maxValue: 500 },
  waist_cm: { label: "Waist", max: 16, minValue: 1, maxValue: 500 },
  hip_cm: { label: "Hips", max: 16, minValue: 1, maxValue: 500 },
  chest_cm: { label: "Chest", max: 16, minValue: 1, maxValue: 500 },
  fitness_goals: { label: "Fitness goals", max: 1000 },
  medical_history: { label: "Medical history", max: 1000 },
  allergies: { label: "Food allergies", max: 1000 },
  dietary_restrictions: { label: "Dietary restrictions", max: 1000 },
  food_preferences: { label: "Food preferences", max: 1000 },
} as const;

export type IntakeField = keyof typeof intakeFields;
export type IntakeAnswers = Partial<Record<IntakeField, string>>;

export class IntakeAnswerError extends Error {}

export function parseIntakeAnswers(value: unknown): IntakeAnswers {
  if (!isObject(value) || Object.keys(value).some(key => !Object.hasOwn(intakeFields, key))) {
    throw new IntakeAnswerError("Supply only the intake form fields.");
  }
  const answers: IntakeAnswers = {};
  for (const field of Object.keys(intakeFields) as IntakeField[]) {
    const raw = value[field];
    if (raw === undefined) continue;
    if (typeof raw !== "string" || raw.length > intakeFields[field].max) {
      throw new IntakeAnswerError(`${intakeFields[field].label} is invalid or too long.`);
    }
    if (raw.trim()) answers[field] = raw.trim();
  }
  return answers;
}

export function intakeAge(value: string, today: Date): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw invalidBirthDate();
  const birth = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(birth.getTime()) || birth.toISOString().slice(0, 10) !== value) {
    throw invalidBirthDate();
  }
  let age = today.getUTCFullYear() - birth.getUTCFullYear();
  if (today.getUTCMonth() < birth.getUTCMonth() ||
      (today.getUTCMonth() === birth.getUTCMonth() && today.getUTCDate() < birth.getUTCDate())) {
    age--;
  }
  if (age < 1 || age > 120) throw invalidBirthDate();
  return age;
}

function invalidBirthDate(): IntakeAnswerError {
  return new IntakeAnswerError("Enter a valid date of birth for an age from 1 to 120.");
}

export function ageRequiresGuardian(answers: IntakeAnswers, today: Date): boolean {
  const entered = answers.age;
  const birthDate = answers.date_of_birth;
  if (entered !== undefined && (!/^\d{1,3}$/.test(entered) ||
      Number(entered) < 1 || Number(entered) > 120)) {
    throw new IntakeAnswerError("Enter a whole age from 1 to 120.");
  }
  const birthAge = birthDate === undefined ? undefined : intakeAge(birthDate, today);
  return (entered !== undefined && Number(entered) < 18) ||
    (birthAge !== undefined && birthAge < 18);
}

export function validateIntakeSubmission(answers: IntakeAnswers, today = new Date()): number {
  const required = [
    "full_name", "age", "date_of_birth", "height_cm", "weight_kg", "fitness_goals",
    "medical_history", "allergies", "dietary_restrictions", "food_preferences",
  ] as const;
  for (const field of required) {
    if (!answers[field]) throw new IntakeAnswerError(`${intakeFields[field].label} is required.`);
  }
  if (!/^\d{1,3}$/.test(answers.age!) || Number(answers.age) !== intakeAge(answers.date_of_birth!, today)) {
    throw new IntakeAnswerError("Age must match the date of birth you entered.");
  }
  const { contact_email: email, contact_phone: phone } = answers;
  if (!email && !phone) throw new IntakeAnswerError("Enter a contact email or phone number.");
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new IntakeAnswerError("Enter a valid contact email.");
  }
  if (phone && (!/^\+?[0-9 ().-]+$/.test(phone) ||
      !/^\d{7,15}$/.test(phone.replace(/\D/g, "")))) {
    throw new IntakeAnswerError("Enter a phone number with 7 to 15 digits.");
  }
  for (const field of ["height_cm", "weight_kg", "waist_cm", "hip_cm", "chest_cm"] as const) {
    const value = answers[field];
    if (value === undefined) continue;
    const { label, minValue, maxValue } = intakeFields[field];
    const number = Number(value);
    if (!/^\d+(?:\.\d+)?$/.test(value) || number < minValue || number > maxValue) {
      throw new IntakeAnswerError(`${label} must be between ${minValue} and ${maxValue}.`);
    }
  }
  const bmi = Number(answers.weight_kg) / (Number(answers.height_cm) / 100) ** 2;
  return Math.round(bmi * 10) / 10;
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
