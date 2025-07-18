import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/splash/splash_screen.dart';

class ProfilePage extends StatefulWidget {
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = '';
  String email = '';
  String age = '';
  String gender = '';
  String maxHr = '';
  bool isLoading = true;
  bool isEditing = false;
  bool isSaving = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  String _selectedGender = 'male';

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> fetchUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final response = await http.get(
      Uri.parse('https://authcheck.co/getuser'),
      headers: {
        'Accept': '*/*',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final user = data['user'] ?? {};
      setState(() {
        name = user['name'] ?? '';
        email = user['email'] ?? '';
        age = user['age']?.toString() ?? '';
        gender = user['gender'] ?? '';
        maxHr = user['maxhr']?.toString() ?? '';
        isLoading = false;

        // Initialize controllers with current values
        _nameController.text = name;
        _ageController.text = age;
        _selectedGender =
            gender.toLowerCase().isNotEmpty ? gender.toLowerCase() : 'male';
      });
      debugPrint(response.body);
    } else {
      setState(() {
        isLoading = false;
      });
      // Optionally show error
    }
  }

  Future<void> updateUserData() async {
    setState(() {
      isSaving = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    if (token == null) {
      setState(() {
        isSaving = false;
      });
      _showSnackBar('No authentication token found', Colors.red);
      return;
    }

    final response = await http.post(
      Uri.parse('https://authcheck.co/updateuser'),
      headers: {
        'Accept': '*/*',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'gender': _selectedGender,
      }),
    );

    setState(() {
      isSaving = false;
    });

    if (response.statusCode == 200) {
      setState(() {
        name = _nameController.text.trim();
        age = _ageController.text.trim();
        gender = _selectedGender;
        isEditing = false;
      });
      _showSnackBar('Profile updated successfully!', Colors.green);
    } else {
      _showSnackBar('Failed to update profile', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: color,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    );
  }

  void _toggleEditMode() {
    setState(() {
      if (isEditing) {
        // Reset controllers to original values
        _nameController.text = name;
        _ageController.text = age;
        _selectedGender =
            gender.toLowerCase().isNotEmpty ? gender.toLowerCase() : 'male';
      }
      isEditing = !isEditing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'TheWitcher',
            fontSize: 24,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              onPressed: _toggleEditMode,
              tooltip: 'Edit Profile',
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SplashScreen()),
              );
            },
            tooltip: 'Logout',
          ),
        ],
        backgroundColor: const Color(0xFF0A0D29),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF0A0D29),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Profile Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E2A78), Color(0xFF2D3A96)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Profile Avatar
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Name Display
                        Text(
                          name.isNotEmpty ? name : 'No Name',
                          style: const TextStyle(
                            fontFamily: 'TheWitcher',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // Email Display
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
                              fontFamily: 'TheWitcher',
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Profile Details Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1F3A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section Title
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Profile Information',
                              style: TextStyle(
                                fontFamily: 'TheWitcher',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            if (isEditing)
                              TextButton(
                                onPressed: _toggleEditMode,
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontFamily: 'TheWitcher',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Profile Fields
                        _buildProfileField(
                            'Name', name, _nameController, TextInputType.text),
                        const SizedBox(height: 20),
                        _buildProfileField(
                            'Age', age, _ageController, TextInputType.number),
                        const SizedBox(height: 20),
                        _buildGenderField(),
                        const SizedBox(height: 20),
                        _buildReadOnlyField('Max HR', maxHr, Icons.favorite),

                        // Save Button at bottom of form
                        if (isEditing) ...[
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isSaving ? null : updateUserData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                elevation: 2,
                              ),
                              child: isSaving
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Saving...',
                                          style: TextStyle(
                                            fontFamily: 'TheWitcher',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        fontFamily: 'TheWitcher',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Delete Account Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D1B1B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Danger Zone',
                          style: TextStyle(
                            fontFamily: 'TheWitcher',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This action cannot be undone. Your account and all data will be permanently deleted.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                            fontFamily: 'TheWitcher',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _showDeleteConfirmation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Delete Account',
                            style: TextStyle(
                              fontFamily: 'TheWitcher',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileField(String label, String currentValue,
      TextEditingController controller, TextInputType inputType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.9),
            fontFamily: 'TheWitcher',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isEditing ? const Color(0xFF2A2F4A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEditing
                  ? const Color(0xFF4A90E2)
                  : Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: isEditing
              ? TextFormField(
                  controller: controller,
                  keyboardType: inputType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'TheWitcher',
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: InputBorder.none,
                    hintText: 'Enter $label',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontFamily: 'TheWitcher',
                    ),
                  ),
                )
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _getIconForField(label),
                        color: const Color(0xFF4A90E2),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          currentValue.isNotEmpty ? currentValue : 'Not set',
                          style: TextStyle(
                            color: currentValue.isNotEmpty
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                            fontSize: 16,
                            fontFamily: 'TheWitcher',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGenderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.9),
            fontFamily: 'TheWitcher',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isEditing ? const Color(0xFF2A2F4A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEditing
                  ? const Color(0xFF4A90E2)
                  : Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: isEditing
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedGender,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2F4A),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'TheWitcher',
                      ),
                      items: ['male', 'female', 'other'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value.substring(0, 1).toUpperCase() +
                                value.substring(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'TheWitcher',
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedGender = newValue;
                          });
                        }
                      },
                    ),
                  ),
                )
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: Color(0xFF4A90E2),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          gender.isNotEmpty
                              ? gender.substring(0, 1).toUpperCase() +
                                  gender.substring(1)
                              : 'Not set',
                          style: TextStyle(
                            color: gender.isNotEmpty
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                            fontSize: 16,
                            fontFamily: 'TheWitcher',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.9),
            fontFamily: 'TheWitcher',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.red.withOpacity(0.8),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value.isNotEmpty ? value : 'Not calculated',
                    style: TextStyle(
                      color: value.isNotEmpty
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      fontSize: 16,
                      fontFamily: 'TheWitcher',
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Read Only',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      fontFamily: 'TheWitcher',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getIconForField(String label) {
    switch (label.toLowerCase()) {
      case 'name':
        return Icons.person_outline;
      case 'age':
        return Icons.cake_outlined;
      case 'email':
        return Icons.email_outlined;
      default:
        return Icons.info_outline;
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(
                'Delete Account',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'TheWitcher',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently lost.',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'TheWitcher',
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                  fontFamily: 'TheWitcher',
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAccount();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontFamily: 'TheWitcher',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      },
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    if (token != null) {
      final response = await http.post(
        Uri.parse('https://authcheck.co/deleteuser'),
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
        },
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (response.statusCode == 200) {
        await prefs.remove('token');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SplashScreen()),
        );
      } else {
        _showSnackBar('Error deleting account', Colors.red);
      }
    } else {
      Navigator.of(context).pop(); // Close loading dialog
      _showSnackBar('No token found', Colors.red);
    }
  }
}
