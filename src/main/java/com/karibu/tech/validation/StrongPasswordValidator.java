package com.karibu.tech.validation;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Validator for strong password enforcement.
 * 
 * SECURITY CRITICAL: This prevents weak passwords that are:
 * - Too short
 * - Lacking complexity (no uppercase, lowercase, digits, special chars)
 * - Common/easily guessable (password123, admin, etc.)
 */
public class StrongPasswordValidator implements ConstraintValidator<StrongPassword, String> {

    private static final int MIN_LENGTH = 12;
    private static final Pattern UPPERCASE_PATTERN = Pattern.compile(".*[A-Z].*");
    private static final Pattern LOWERCASE_PATTERN = Pattern.compile(".*[a-z].*");
    private static final Pattern DIGIT_PATTERN = Pattern.compile(".*\\d.*");
    private static final Pattern SPECIAL_CHAR_PATTERN = Pattern.compile(".*[@#$%^&+=!*()_\\-.].*");

    // Common weak passwords to block
    private static final List<String> COMMON_PASSWORDS = Arrays.asList(
            "password", "password123", "123456", "12345678", "123456789",
            "admin", "admin123", "qwerty", "letmein", "welcome",
            "monkey", "dragon", "master", "sunshine", "princess",
            "football", "iloveyou", "trustno1", "abc123", "starwars",
            "zugfahrt", "zugfahrt123", "zeiterfassung");

    @Override
    public boolean isValid(String password, ConstraintValidatorContext context) {
        if (password == null) {
            return false;
        }

        // Check minimum length
        if (password.length() < MIN_LENGTH) {
            setCustomMessage(context,
                    "Das Passwort muss mindestens " + MIN_LENGTH + " Zeichen lang sein.");
            return false;
        }

        // Check for uppercase letter
        if (!UPPERCASE_PATTERN.matcher(password).matches()) {
            setCustomMessage(context,
                    "Das Passwort muss mindestens einen Großbuchstaben enthalten.");
            return false;
        }

        // Check for lowercase letter
        if (!LOWERCASE_PATTERN.matcher(password).matches()) {
            setCustomMessage(context,
                    "Das Passwort muss mindestens einen Kleinbuchstaben enthalten.");
            return false;
        }

        // Check for digit
        if (!DIGIT_PATTERN.matcher(password).matches()) {
            setCustomMessage(context,
                    "Das Passwort muss mindestens eine Ziffer enthalten.");
            return false;
        }

        // Check for special character
        if (!SPECIAL_CHAR_PATTERN.matcher(password).matches()) {
            setCustomMessage(context,
                    "Das Passwort muss mindestens ein Sonderzeichen (@#$%^&+=!*()_-.) enthalten.");
            return false;
        }

        // Check against common passwords (case-insensitive)
        if (COMMON_PASSWORDS.contains(password.toLowerCase())) {
            setCustomMessage(context,
                    "Dieses Passwort ist zu häufig verwendet und unsicher. Bitte wählen Sie ein anderes.");
            return false;
        }

        // Check for sequential characters (123, abc, etc.)
        if (containsSequentialChars(password)) {
            setCustomMessage(context,
                    "Das Passwort sollte keine einfachen Sequenzen enthalten (z.B. 123, abc).");
            return false;
        }

        return true;
    }

    private boolean containsSequentialChars(String password) {
        String lowerPassword = password.toLowerCase();

        // Check for sequential numbers (123, 234, etc.)
        for (int i = 0; i < lowerPassword.length() - 2; i++) {
            char c1 = lowerPassword.charAt(i);
            char c2 = lowerPassword.charAt(i + 1);
            char c3 = lowerPassword.charAt(i + 2);

            if (Character.isDigit(c1) && Character.isDigit(c2) && Character.isDigit(c3)) {
                if (c2 == c1 + 1 && c3 == c2 + 1) {
                    return true; // Found sequential numbers
                }
            }

            if (Character.isLetter(c1) && Character.isLetter(c2) && Character.isLetter(c3)) {
                if (c2 == c1 + 1 && c3 == c2 + 1) {
                    return true; // Found sequential letters (abc, bcd, etc.)
                }
            }
        }

        return false;
    }

    private void setCustomMessage(ConstraintValidatorContext context, String message) {
        context.disableDefaultConstraintViolation();
        context.buildConstraintViolationWithTemplate(message).addConstraintViolation();
    }
}
