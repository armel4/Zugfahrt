package com.karibu.tech.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.*;

/**
 * Custom annotation for strong password validation.
 * 
 * Password requirements:
 * - Minimum 12 characters
 * - At least one uppercase letter
 * - At least one lowercase letter
 * - At least one digit
 * - At least one special character (@#$%^&+=!*()_-.)
 * - No common patterns (123456, password, etc.)
 */
@Documented
@Constraint(validatedBy = StrongPasswordValidator.class)
@Target({ ElementType.FIELD, ElementType.PARAMETER })
@Retention(RetentionPolicy.RUNTIME)
public @interface StrongPassword {

    String message() default "Das Passwort erfüllt nicht die Sicherheitsanforderungen. " +
            "Mindestens 12 Zeichen, Groß- und Kleinbuchstaben, Zahlen und Sonderzeichen erforderlich.";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
