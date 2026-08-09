import '../repositories/clinic_repository.dart';

const otherProfessionalTitle = 'Other';

const Map<String, List<String>> _titlesByRoleCode = {
  'veterinarian': [
    'Veterinary Doctor',
    'Veterinary Surgeon',
    'Senior Veterinarian',
    'Veterinary Consultant',
    'Medical Director',
    otherProfessionalTitle,
  ],
  'veterinary_nurse': [
    'Veterinary Nurse',
    'Veterinary Technician',
    'Senior Veterinary Nurse',
    'Animal Health Technician',
    otherProfessionalTitle,
  ],
  'receptionist': [
    'Receptionist',
    'Front Desk Officer',
    'Client Service Officer',
    'Customer Care Officer',
    otherProfessionalTitle,
  ],
  'laboratory_staff': [
    'Laboratory Scientist',
    'Laboratory Technician',
    'Laboratory Assistant',
    'Laboratory Manager',
    otherProfessionalTitle,
  ],
  'pharmacist': [
    'Pharmacist',
    'Veterinary Pharmacist',
    'Pharmacy Officer',
    'Pharmacy Manager',
    otherProfessionalTitle,
  ],
  'cashier': [
    'Billing Officer',
    'Accounts Officer',
    'Accountant',
    'Finance Officer',
    otherProfessionalTitle,
  ],
  'practice_manager': [
    'Practice Manager',
    'Administrative Officer',
    'Office Manager',
    'Operations Manager',
    otherProfessionalTitle,
  ],
  'inventory_officer': [
    'Inventory Officer',
    'Stock Control Officer',
    'Procurement Officer',
    'Store Manager',
    otherProfessionalTitle,
  ],
  'sales_representative': [
    'Sales Representative',
    'Sales Officer',
    'Business Development Officer',
    otherProfessionalTitle,
  ],
};

List<String> professionalTitlesForRole(ClinicRoleOption role) {
  return _titlesByRoleCode[role.code] ?? const [otherProfessionalTitle];
}

bool professionalTitleCatalogueCovers(Iterable<String> roleCodes) {
  return roleCodes.every(
    (code) => _titlesByRoleCode[code]?.lastOrNull == otherProfessionalTitle,
  );
}
