// Visibility settings
View[0].Visible = 0;
View[2].Visible = 0;
View[3].Visible = 0;
View[1].Visible = 1;
View[4].Visible = 1;
View[5].Visible = 1;

// E-Norm settings
View[1].SaturateValues = 1;
View[1].RangeType = 2;
View[1].CustomMin = 0;
View[1].CustomMax = 2;

// Surface Visibilitly
Hide {:}
Recursive Show { Volume{2}; }

// Set orientation of figure
General.Trackball = 0;
General.RotationX = 300;
General.RotationY = 0;
General.RotationZ = 185;
General.TranslationX = 0;
General.TranslationY = 0;
General.TranslationZ = 0;
General.ScaleX = 1.7;
General.ScaleY = 1.7;
General.ScaleZ = 1.7;

//Scalp2Cortex settings
View[4].LineWidth = 8;
