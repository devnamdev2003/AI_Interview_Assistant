import os
import django
import requests

# Set the Django settings module for the project
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'AIIA.settings')  # Adjust accordingly
django.setup()
data = [
    {"name": "South Georgia",
     "cca2": "GS"
     },
    {"name": "Grenada",
     "cca2": "GD"
     },
    {"name": "Switzerland",
     "cca2": "CH"
     },
    {"name": "Sierra Leone",
     "cca2": "SL"
     },
    {"name": "Hungary",
     "cca2": "HU"
     },
    {"name": "Taiwan",
     "cca2": "TW"
     },
    {"name": "Wallis and Futuna",
     "cca2": "WF"
     },
    {"name": "Barbados",
     "cca2": "BB"
     },
    {"name": "Pitcairn Islands",
     "cca2": "PN"
     },
    {"name": "Ivory Coast",
     "cca2": "CI"
     },
    {"name": "Tunisia",
     "cca2": "TN"
     },
    {"name": "Italy",
     "cca2": "IT"
     },
    {"name": "Benin",
     "cca2": "BJ"
     },
    {"name": "Indonesia",
     "cca2": "ID"
     },
    {"name": "Cape Verde",
     "cca2": "CV"
     },
    {"name": "Saint Kitts and Nevis",
     "cca2": "KN"
     },
    {"name": "Laos",
     "cca2": "LA"
     },
    {"name": "Caribbean Netherlands",
     "cca2": "BQ"
     },
    {"name": "Uganda",
     "cca2": "UG"
     },
    {"name": "Andorra",
     "cca2": "AD"
     },
    {"name": "Burundi",
     "cca2": "BI"
     },
    {"name": "South Africa",
     "cca2": "ZA"
     },
    {"name": "France",
     "cca2": "FR"
     },
    {"name": "Libya",
     "cca2": "LY"
     },
    {"name": "Mexico",
     "cca2": "MX"
     },
    {"name": "Gabon",
     "cca2": "GA"
     },
    {"name": "Northern Mariana Islands",
     "cca2": "MP"
     },
    {"name": "North Macedonia",
     "cca2": "MK"
     },
    {"name": "China",
     "cca2": "CN"
     },
    {"name": "Yemen",
     "cca2": "YE"
     },
    {"name": "Saint Barthélemy",
     "cca2": "BL"
     },
    {"name": "Guernsey",
     "cca2": "GG"
     },
    {"name": "Solomon Islands",
     "cca2": "SB"
     },
    {"name": "Svalbard and Jan Mayen",
     "cca2": "SJ"
     },
    {"name": "Faroe Islands",
     "cca2": "FO"
     },
    {"name": "Uzbekistan",
     "cca2": "UZ"
     },
    {"name": "Egypt",
     "cca2": "EG"
     },
    {"name": "Senegal",
     "cca2": "SN"
     },
    {"name": "Sri Lanka",
     "cca2": "LK"
     },
    {"name": "Palestine",
     "cca2": "PS"
     },
    {"name": "Bangladesh",
     "cca2": "BD"
     },
    {"name": "Peru",
     "cca2": "PE"
     },
    {"name": "Singapore",
     "cca2": "SG"
     },
    {"name": "Turkey",
     "cca2": "TR"
     },
    {"name": "Afghanistan",
     "cca2": "AF"
     },
    {"name": "Aruba",
     "cca2": "AW"
     },
    {"name": "Cook Islands",
     "cca2": "CK"
     },
    {"name": "United Kingdom",
     "cca2": "GB"
     },
    {"name": "Zambia",
     "cca2": "ZM"
     },
    {"name": "Finland",
     "cca2": "FI"
     },
    {"name": "Niger",
     "cca2": "NE"
     },
    {"name": "Christmas Island",
     "cca2": "CX"
     },
    {"name": "Tokelau",
     "cca2": "TK"
     },
    {"name": "Guinea-Bissau",
     "cca2": "GW"
     },
    {"name": "Azerbaijan",
     "cca2": "AZ"
     },
    {"name": "Réunion",
     "cca2": "RE"
     },
    {"name": "Djibouti",
     "cca2": "DJ"
     },
    {"name": "North Korea",
     "cca2": "KP"
     },
    {"name": "Mauritius",
     "cca2": "MU"
     },
    {"name": "Montserrat",
     "cca2": "MS"
     },
    {"name": "United States Virgin Islands",
     "cca2": "VI"
     },
    {"name": "Colombia",
     "cca2": "CO"
     },
    {"name": "Greece",
     "cca2": "GR"
     },
    {"name": "Croatia",
     "cca2": "HR"
     },
    {"name": "Morocco",
     "cca2": "MA"
     },
    {"name": "Algeria",
     "cca2": "DZ"
     },
    {"name": "Antarctica",
     "cca2": "AQ"
     },
    {"name": "Netherlands",
     "cca2": "NL"
     },
    {"name": "Sudan",
     "cca2": "SD"
     },
    {"name": "Fiji",
     "cca2": "FJ"
     },
    {"name": "Liechtenstein",
     "cca2": "LI"
     },
    {"name": "Nepal",
     "cca2": "NP"
     },
    {"name": "Puerto Rico",
     "cca2": "PR"
     },
    {"name": "Georgia",
     "cca2": "GE"
     },
    {"name": "Pakistan",
     "cca2": "PK"
     },
    {"name": "Monaco",
     "cca2": "MC"
     },
    {"name": "Botswana",
     "cca2": "BW"
     },
    {"name": "Lebanon",
     "cca2": "LB"
     },
    {"name": "Papua New Guinea",
     "cca2": "PG"
     },
    {"name": "Mayotte",
     "cca2": "YT"
     },
    {"name": "Dominican Republic",
     "cca2": "DO"
     },
    {"name": "Norfolk Island",
     "cca2": "NF"
     },
    {"name": "Bouvet Island",
     "cca2": "BV"
     },
    {"name": "Qatar",
     "cca2": "QA"
     },
    {"name": "Madagascar",
     "cca2": "MG"
     },
    {"name": "India",
     "cca2": "IN"
     },
    {"name": "Syria",
     "cca2": "SY"
     },
    {"name": "Montenegro",
     "cca2": "ME"
     },
    {"name": "Eswatini",
     "cca2": "SZ"
     },
    {"name": "Paraguay",
     "cca2": "PY"
     },
    {"name": "El Salvador",
     "cca2": "SV"
     },
    {"name": "Ukraine",
     "cca2": "UA"
     },
    {"name": "Isle of Man",
     "cca2": "IM"
     },
    {"name": "Namibia",
     "cca2": "NA"
     },
    {"name": "United Arab Emirates",
     "cca2": "AE"
     },
    {"name": "Bulgaria",
     "cca2": "BG"
     },
    {"name": "Greenland",
     "cca2": "GL"
     },
    {"name": "Germany",
     "cca2": "DE"
     },
    {"name": "Cambodia",
     "cca2": "KH"
     },
    {"name": "Iraq",
     "cca2": "IQ"
     },
    {"name": "French Southern and Antarctic Lands",
     "cca2": "TF"
     },
    {"name": "Sweden",
     "cca2": "SE"
     },
    {"name": "Cuba",
     "cca2": "CU"
     },
    {"name": "Kyrgyzstan",
     "cca2": "KG"
     },
    {"name": "Russia",
     "cca2": "RU"
     },
    {"name": "Malaysia",
     "cca2": "MY"
     },
    {"name": "São Tomé and Príncipe",
     "cca2": "ST"
     },
    {"name": "Cyprus",
     "cca2": "CY"
     },
    {"name": "Canada",
     "cca2": "CA"
     },
    {"name": "Malawi",
     "cca2": "MW"
     },
    {"name": "Saudi Arabia",
     "cca2": "SA"
     },
    {"name": "Bosnia and Herzegovina",
     "cca2": "BA"
     },
    {"name": "Ethiopia",
     "cca2": "ET"
     },
    {"name": "Spain",
     "cca2": "ES"
     },
    {"name": "Slovenia",
     "cca2": "SI"
     },
    {"name": "Oman",
     "cca2": "OM"
     },
    {"name": "Saint Pierre and Miquelon",
     "cca2": "PM"
     },
    {"name": "Macau",
     "cca2": "MO"
     },
    {"name": "San Marino",
     "cca2": "SM"
     },
    {"name": "Lesotho",
     "cca2": "LS"
     },
    {"name": "Marshall Islands",
     "cca2": "MH"
     },
    {"name": "Sint Maarten",
     "cca2": "SX"
     },
    {"name": "Iceland",
     "cca2": "IS"
     },
    {"name": "Luxembourg",
     "cca2": "LU"
     },
    {"name": "Argentina",
     "cca2": "AR"
     },
    {"name": "Turks and Caicos Islands",
     "cca2": "TC"
     },
    {"name": "Nauru",
     "cca2": "NR"
     },
    {"name": "Cocos (Keeling) Islands",
     "cca2": "CC"
     },
    {"name": "Western Sahara",
     "cca2": "EH"
     },
    {"name": "Dominica",
     "cca2": "DM"
     },
    {"name": "Costa Rica",
     "cca2": "CR"
     },
    {"name": "Australia",
     "cca2": "AU"
     },
    {"name": "Thailand",
     "cca2": "TH"
     },
    {"name": "Haiti",
     "cca2": "HT"
     },
    {"name": "Tuvalu",
     "cca2": "TV"
     },
    {"name": "Honduras",
     "cca2": "HN"
     },
    {"name": "Equatorial Guinea",
     "cca2": "GQ"
     },
    {"name": "Saint Lucia",
     "cca2": "LC"
     },
    {"name": "French Polynesia",
     "cca2": "PF"
     },
    {"name": "Belarus",
     "cca2": "BY"
     },
    {"name": "Latvia",
     "cca2": "LV"
     },
    {"name": "Palau",
     "cca2": "PW"
     },
    {"name": "Guadeloupe",
     "cca2": "GP"
     },
    {"name": "Philippines",
     "cca2": "PH"
     },
    {"name": "Gibraltar",
     "cca2": "GI"
     },
    {"name": "Denmark",
     "cca2": "DK"
     },
    {"name": "Cameroon",
     "cca2": "CM"
     },
    {"name": "Guinea",
     "cca2": "GN"
     },
    {"name": "Bahrain",
     "cca2": "BH"
     },
    {"name": "Suriname",
     "cca2": "SR"
     },
    {"name": "DR Congo",
     "cca2": "CD"
     },
    {"name": "Somalia",
     "cca2": "SO"
     },
    {"name": "Czechia",
     "cca2": "CZ"
     },
    {"name": "New Caledonia",
     "cca2": "NC"
     },
    {"name": "Vanuatu",
     "cca2": "VU"
     },
    {"name": "Saint Helena, Ascension and Tristan da Cunha",
     "cca2": "SH"
     },
    {"name": "Togo",
     "cca2": "TG"
     },
    {"name": "British Virgin Islands",
     "cca2": "VG"
     },
    {"name": "Kenya",
     "cca2": "KE"
     },
    {"name": "Niue",
     "cca2": "NU"
     },
    {"name": "Heard Island and McDonald Islands",
     "cca2": "HM"
     },
    {"name": "Rwanda",
     "cca2": "RW"
     },
    {"name": "Estonia",
     "cca2": "EE"
     },
    {"name": "Romania",
     "cca2": "RO"
     },
    {"name": "Trinidad and Tobago",
     "cca2": "TT"
     },
    {"name": "Guyana",
     "cca2": "GY"
     },
    {"name": "Timor-Leste",
     "cca2": "TL"
     },
    {"name": "Vietnam",
     "cca2": "VN"
     },
    {"name": "Uruguay",
     "cca2": "UY"
     },
    {"name": "Vatican City",
     "cca2": "VA"
     },
    {"name": "Hong Kong",
     "cca2": "HK"
     },
    {"name": "Austria",
     "cca2": "AT"
     },
    {"name": "Antigua and Barbuda",
     "cca2": "AG"
     },
    {"name": "Turkmenistan",
     "cca2": "TM"
     },
    {"name": "Mozambique",
     "cca2": "MZ"
     },
    {"name": "Panama",
     "cca2": "PA"
     },
    {"name": "Micronesia",
     "cca2": "FM"
     },
    {"name": "Ireland",
     "cca2": "IE"
     },
    {"name": "Curaçao",
     "cca2": "CW"
     },
    {"name": "French Guiana",
     "cca2": "GF"
     },
    {"name": "Norway",
     "cca2": "NO"
     },
    {"name": "Åland Islands",
     "cca2": "AX"
     },
    {"name": "Central African Republic",
     "cca2": "CF"
     },
    {"name": "Burkina Faso",
     "cca2": "BF"
     },
    {"name": "Eritrea",
     "cca2": "ER"
     },
    {"name": "Tanzania",
     "cca2": "TZ"
     },
    {"name": "South Korea",
     "cca2": "KR"
     },
    {"name": "Jordan",
     "cca2": "JO"
     },
    {"name": "Mauritania",
     "cca2": "MR"
     },
    {"name": "Lithuania",
     "cca2": "LT"
     },
    {"name": "United States Minor Outlying Islands",
     "cca2": "UM"
     },
    {"name": "Slovakia",
     "cca2": "SK"
     },
    {"name": "Angola",
     "cca2": "AO"
     },
    {"name": "Kazakhstan",
     "cca2": "KZ"
     },
    {"name": "Moldova",
     "cca2": "MD"
     },
    {"name": "Mali",
     "cca2": "ML"
     },
    {"name": "Falkland Islands",
     "cca2": "FK"
     },
    {"name": "Armenia",
     "cca2": "AM"
     },
    {"name": "Samoa",
     "cca2": "WS"
     },
    {"name": "Jersey",
     "cca2": "JE"
     },
    {"name": "Japan",
     "cca2": "JP"
     },
    {"name": "Bolivia",
     "cca2": "BO"
     },
    {"name": "Chile",
     "cca2": "CL"
     },
    {"name": "United States",
     "cca2": "US"
     },
    {"name": "Saint Vincent and the Grenadines",
     "cca2": "VC"
     },
    {"name": "Bermuda",
     "cca2": "BM"
     },
    {"name": "Seychelles",
     "cca2": "SC"
     },
    {"name": "British Indian Ocean Territory",
     "cca2": "IO"
     },
    {"name": "Guatemala",
     "cca2": "GT"
     },
    {"name": "Ecuador",
     "cca2": "EC"
     },
    {"name": "Martinique",
     "cca2": "MQ"
     },
    {"name": "Tajikistan",
     "cca2": "TJ"
     },
    {"name": "Malta",
     "cca2": "MT"
     },
    {"name": "Gambia",
     "cca2": "GM"
     },
    {"name": "Nigeria",
     "cca2": "NG"
     },
    {"name": "Bahamas",
     "cca2": "BS"
     },
    {"name": "Kosovo",
     "cca2": "XK"
     },
    {"name": "Kuwait",
     "cca2": "KW"
     },
    {"name": "Maldives",
     "cca2": "MV"
     },
    {"name": "South Sudan",
     "cca2": "SS"
     },
    {"name": "Iran",
     "cca2": "IR"
     },
    {"name": "Albania",
     "cca2": "AL"
     },
    {"name": "Brazil",
     "cca2": "BR"
     },
    {"name": "Serbia",
     "cca2": "RS"
     },
    {"name": "Belize",
     "cca2": "BZ"
     },
    {"name": "Myanmar",
     "cca2": "MM"
     },
    {"name": "Bhutan",
     "cca2": "BT"
     },
    {"name": "Venezuela",
     "cca2": "VE"
     },
    {"name": "Liberia",
     "cca2": "LR"
     },
    {"name": "Jamaica",
     "cca2": "JM"
     },
    {"name": "Poland",
     "cca2": "PL"
     },
    {"name": "Cayman Islands",
     "cca2": "KY"
     },
    {"name": "Brunei",
     "cca2": "BN"
     },
    {"name": "Comoros",
     "cca2": "KM"
     },
    {"name": "Guam",
     "cca2": "GU"
     },
    {"name": "Tonga",
     "cca2": "TO"
     },
    {"name": "Kiribati",
     "cca2": "KI"
     },
    {"name": "Ghana",
     "cca2": "GH"
     },
    {"name": "Chad",
     "cca2": "TD"
     },
    {"name": "Zimbabwe",
     "cca2": "ZW"
     },
    {"name": "Saint Martin",
     "cca2": "MF"
     },
    {"name": "Mongolia",
     "cca2": "MN"
     },
    {"name": "Portugal",
     "cca2": "PT"
     },
    {"name": "American Samoa",
     "cca2": "AS"
     },
    {"name": "Republic of the Congo",
     "cca2": "CG"
     },
    {"name": "Belgium",
     "cca2": "BE"
     },
    {"name": "Israel",
     "cca2": "IL"
     },
    {"name": "New Zealand",
     "cca2": "NZ"
     },
    {"name": "Nicaragua",
     "cca2": "NI"
     },
    {"name": "Anguilla",
     "cca2": "AI"
     },
]

# Now you can import the model
from api.models.utility.CountriesModel import Country  
for country in data:
    # Extract the country name and country code (using common name and cioc for the code)
    country_name = country["name"]
    country_code = country["cca2"]
    
    # Only insert if country_name and country_code are present
    if country_name and country_code:
        # Create or update the country record in the database
        Country.objects.update_or_create(
            country_name=country_name,
            country_code=country_code,
            defaults={'is_active': True}
        )
        print(f"Inserted/Updated: {country_name} ({country_code})")

