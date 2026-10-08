                    children: [
                      FulusChip(label: 'Sign in', selected: !creating, onTap: () => _switchMode(_AccountMode.signIn)),
                      FulusChip(label: 'Create account', selected: creating, onTap: () => _switchMode(_AccountMode.create)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FulusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (creating) ...[
                          FulusTextField(label: 'Your name', controller: _nameController, enabled: !_busy),
                          const SizedBox(height: AppSpacing.md),
                          FulusTextField(label: 'Business name', controller: _businessController, enabled: !_busy),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        FulusTextField(
                          label: 'Email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FulusTextField(
                          label: 'Password',
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_busy,
                          helperText: creating ? 'Use at least 8 characters.' : null,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                            onPressed: _busy ? null : () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? FulusIcons.visibility : FulusIcons.visibilityOff),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        if (_awaitingVerification) ...[
                          FulusButton(
                            label: 'I’ve verified my email',
                            loading: _busy,
                            onPressed: _busy ? null : _verifyAndFinish,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        FulusButton(
                          label: creating ? 'Create account' : 'Sign in',
                          loading: _busy,
                          onPressed: _busy ? null : (creating ? _createAccount : _signIn),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}